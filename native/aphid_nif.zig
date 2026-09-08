const beam = @import("beam");
const e = @import("erl_nif");
const c = @import("bridge");
const std = @import("std");

const Database = struct {
    handle: ?*c.aphid_db,
    monitor: e.ErlNifMonitor,
};
const Operation = struct {
    parent: *Database,
    session: u32,
    id: u64,
    owner: e.ErlNifPid,
    monitor: e.ErlNifMonitor,
    cancelled: std.atomic.Value(bool),
};
const Lease = struct {
    parent: *Database,
    session: u32,
    id: u64,
    owner: e.ErlNifPid,
    monitor: e.ErlNifMonitor,
    cancelled: std.atomic.Value(bool),
};
var database_type: ?*e.ErlNifResourceType = null;
var operation_type: ?*e.ErlNifResourceType = null;
var lease_type: ?*e.ErlNifResourceType = null;

fn lease_dtor(_: beam.env, object: ?*anyopaque) callconv(.c) void {
    const lease: *Lease = @ptrCast(@alignCast(object.?));
    _ = c.aphid_lease_release(lease.parent.handle, lease.session, lease.id);
    e.enif_release_resource(lease.parent);
}
fn lease_down(_: beam.env, object: ?*anyopaque, _: [*c]e.ErlNifPid, _: [*c]e.ErlNifMonitor) callconv(.c) void {
    const lease: *Lease = @ptrCast(@alignCast(object.?));
    lease.cancelled.store(true, .release);
    _ = c.aphid_lease_release(lease.parent.handle, lease.session, lease.id);
}

fn database_dtor(_: beam.env, object: ?*anyopaque) callconv(.c) void {
    const db: *Database = @ptrCast(@alignCast(object.?));
    c.aphid_release(db.handle);
}
fn database_down(_: beam.env, object: ?*anyopaque, _: [*c]e.ErlNifPid, _: [*c]e.ErlNifMonitor) callconv(.c) void {
    const db: *Database = @ptrCast(@alignCast(object.?));
    c.aphid_retire(db.handle);
}
fn operation_dtor(_: beam.env, object: ?*anyopaque) callconv(.c) void {
    const op: *Operation = @ptrCast(@alignCast(object.?));
    _ = c.aphid_cancel(op.parent.handle, op.session, op.id, 1);
    e.enif_release_resource(op.parent);
}
fn operation_down(_: beam.env, object: ?*anyopaque, _: [*c]e.ErlNifPid, _: [*c]e.ErlNifMonitor) callconv(.c) void {
    const op: *Operation = @ptrCast(@alignCast(object.?));
    op.cancelled.store(true, .release);
    _ = c.aphid_cancel(op.parent.handle, op.session, op.id, 1);
}

pub fn load(env: beam.env, _: ?*?*anyopaque, _: e.ERL_NIF_TERM) c_int {
    if (c.aphid_bridge_version() != 1) return -1;
    var db_init = e.ErlNifResourceTypeInit{ .dtor = database_dtor, .stop = null, .down = database_down, .members = 3, .dyncall = null };
    var op_init = e.ErlNifResourceTypeInit{ .dtor = operation_dtor, .stop = null, .down = operation_down, .members = 3, .dyncall = null };
    var lease_init = e.ErlNifResourceTypeInit{ .dtor = lease_dtor, .stop = null, .down = lease_down, .members = 3, .dyncall = null };
    database_type = e.enif_init_resource_type(env, "aphid_database", &db_init, e.ERL_NIF_RT_CREATE, null);
    operation_type = e.enif_init_resource_type(env, "aphid_operation", &op_init, e.ERL_NIF_RT_CREATE, null);
    lease_type = e.enif_init_resource_type(env, "aphid_lease", &lease_init, e.ERL_NIF_RT_CREATE, null);
    if (database_type == null or operation_type == null or lease_type == null) return -1;
    const anchor: *Database = @ptrCast(@alignCast(e.enif_alloc_resource(database_type, @sizeOf(Database)) orelse return -1));
    anchor.* = .{ .handle = null, .monitor = undefined };
    // Deliberately retained once per VM: callbacks can never execute unloaded code.
    return 0;
}
pub fn upgrade(_: beam.env, _: ?*?*anyopaque, _: ?*?*anyopaque, _: e.ERL_NIF_TERM) c_int {
    return -1;
}

fn get_database(term: beam.term) !*Database {
    var object: ?*anyopaque = null;
    if (e.enif_get_resource(beam.context.env, term.v, database_type, &object) == 0) return error.InvalidDatabase;
    return @ptrCast(@alignCast(object.?));
}
fn get_operation(term: beam.term) !*Operation {
    var object: ?*anyopaque = null;
    if (e.enif_get_resource(beam.context.env, term.v, operation_type, &object) == 0) return error.InvalidOperation;
    return @ptrCast(@alignCast(object.?));
}
fn get_lease(term: beam.term) !*Lease {
    var object: ?*anyopaque = null;
    if (e.enif_get_resource(beam.context.env, term.v, lease_type, &object) == 0) return error.InvalidLease;
    const lease: *Lease = @ptrCast(@alignCast(object.?));
    var owner: e.ErlNifPid = undefined;
    _ = e.enif_self(beam.context.env, &owner);
    if (e.enif_compare(owner.pid, lease.owner.pid) != 0) return error.ForeignOwner;
    return lease;
}
fn native_error(err: c.aphid_error) beam.term {
    const bytes: [*]const u8 = @ptrCast(&err.message);
    return beam.make(.{ .@"error", err.code, bytes[0..err.length] }, .{});
}
fn get_binary(term: beam.term, limit: usize) ![]const u8 {
    var binary: e.ErlNifBinary = undefined;
    if (e.enif_inspect_binary(beam.context.env, term.v, &binary) == 0) return error.ExpectedBinary;
    if (binary.size > limit) return error.InputTooLarge;
    return binary.data[0..binary.size];
}

pub fn open(path_term: beam.term, sessions: u32, threads: u32) !beam.term {
    return open_configured(path_term, sessions, threads, 64 * 1024 * 1024);
}

pub fn open_configured(path_term: beam.term, sessions: u32, threads: u32, buffer_pool_bytes: u64) !beam.term {
    beam.ignore_when_sema();
    const path = try get_binary(path_term, 4096);
    const object = e.enif_alloc_resource(database_type, @sizeOf(Database)) orelse return error.OutOfMemory;
    const db: *Database = @ptrCast(@alignCast(object));
    db.* = .{ .handle = null, .monitor = undefined };
    defer e.enif_release_resource(object);
    var owner: e.ErlNifPid = undefined;
    _ = e.enif_self(beam.context.env, &owner);
    var err: c.aphid_error = undefined;
    db.handle = c.aphid_open_configured(path.ptr, path.len, sessions, threads, buffer_pool_bytes, &err);
    if (db.handle == null) return native_error(err);
    if (e.enif_monitor_process(beam.context.env, object, &owner, &db.monitor) != 0) return error.OwnerDead;
    return .{ .v = e.enif_make_resource(beam.context.env, object) };
}

fn was_cancelled(object: ?*anyopaque) callconv(.c) c_int {
    const op: *Operation = @ptrCast(@alignCast(object.?));
    return @intFromBool(op.cancelled.load(.acquire));
}
fn complete(object: ?*anyopaque, status: c_int) callconv(.c) c_int {
    const op: *Operation = @ptrCast(@alignCast(object.?));
    defer e.enif_release_resource(object);
    const env = e.enif_alloc_env() orelse return 0;
    defer e.enif_free_env(env);
    const terms = [_]e.ERL_NIF_TERM{
        e.enif_make_atom(env, "aphid_native"),
        e.enif_make_resource(env, object),
        e.enif_make_int(env, status),
    };
    const message = e.enif_make_tuple_from_array(env, &terms, terms.len);
    return e.enif_send(null, &op.owner, env, message);
}

pub fn submit(database: beam.term, session: u32, query_term: beam.term, parameters: beam.term) !beam.term {
    beam.ignore_when_sema();
    return submit_query(try get_database(database), session, 0, query_term, parameters);
}
pub fn submit_lease(lease_term: beam.term, query_term: beam.term, parameters: beam.term) !beam.term {
    beam.ignore_when_sema();
    const lease = try get_lease(lease_term);
    return submit_query(lease.parent, lease.session, lease.id, query_term, parameters);
}
fn new_operation(db: *Database, session: u32) !*Operation {
    const object = e.enif_alloc_resource(operation_type, @sizeOf(Operation)) orelse return error.OutOfMemory;
    const op: *Operation = @ptrCast(@alignCast(object));
    e.enif_keep_resource(db);
    op.* = .{ .parent = db, .session = session, .id = c.aphid_next_id(db.handle), .owner = undefined, .monitor = undefined, .cancelled = std.atomic.Value(bool).init(false) };
    errdefer e.enif_release_resource(object);
    _ = e.enif_self(beam.context.env, &op.owner);
    if (e.enif_monitor_process(beam.context.env, object, &op.owner, &op.monitor) != 0) return error.OwnerDead;
    return op;
}
fn submit_query(db: *Database, session: u32, lease: u64, query_term: beam.term, parameters: beam.term) !beam.term {
    const query = try get_binary(query_term, 1024 * 1024);
    if (!std.unicode.utf8ValidateSlice(query)) return error.InvalidText;
    const op = try new_operation(db, session);
    defer e.enif_release_resource(op);
    var err: c.aphid_error = undefined;
    if (c.aphid_reserve_lease(db.handle, session, op.id, lease, &err) != 0) return native_error(err);
    var input = Input{ .cancelled = &op.cancelled, .parameter = beam.make(.nil, .{}) };
    const params = input.convert(parameters) catch |failure| return input.failure(failure);
    e.enif_keep_resource(op);
    if (c.aphid_submit_params(db.handle, session, op.id, query.ptr, query.len, params, op, complete, was_cancelled, &err) != 0) {
        e.enif_release_resource(op);
        return native_error(err);
    }
    return .{ .v = e.enif_make_resource(beam.context.env, op) };
}
pub fn lease_acquire(database: beam.term, session: u32) !beam.term {
    beam.ignore_when_sema();
    const db = try get_database(database);
    const object = e.enif_alloc_resource(lease_type, @sizeOf(Lease)) orelse return error.OutOfMemory;
    const lease: *Lease = @ptrCast(@alignCast(object));
    e.enif_keep_resource(db);
    lease.* = .{ .parent = db, .session = session, .id = c.aphid_next_id(db.handle), .owner = undefined, .monitor = undefined, .cancelled = std.atomic.Value(bool).init(false) };
    defer e.enif_release_resource(object);
    _ = e.enif_self(beam.context.env, &lease.owner);
    if (e.enif_monitor_process(beam.context.env, object, &lease.owner, &lease.monitor) != 0) return error.OwnerDead;
    var err: c.aphid_error = undefined;
    if (c.aphid_lease_acquire(db.handle, session, lease.id, &err) != 0) return native_error(err);
    if (lease.cancelled.load(.acquire)) {
        _ = c.aphid_lease_release(db.handle, session, lease.id);
        return error.OwnerDead;
    }
    return .{ .v = e.enif_make_resource(beam.context.env, object) };
}
pub fn lease_release(lease_term: beam.term) !bool {
    const lease = try get_lease(lease_term);
    return c.aphid_lease_release(lease.parent.handle, lease.session, lease.id) != 0;
}
pub fn transaction_control(lease_term: beam.term, control: u32) !beam.term {
    beam.ignore_when_sema();
    const lease = try get_lease(lease_term);
    const op = try new_operation(lease.parent, lease.session);
    defer e.enif_release_resource(op);
    var err: c.aphid_error = undefined;
    e.enif_keep_resource(op);
    if (c.aphid_transaction_control(lease.parent.handle, lease.session, op.id, lease.id, control, op, complete, was_cancelled, &err) != 0) {
        e.enif_release_resource(op);
        return native_error(err);
    }
    return .{ .v = e.enif_make_resource(beam.context.env, op) };
}
pub fn close(database: beam.term) !void {
    c.aphid_retire((try get_database(database)).handle);
}
pub fn closed(database: beam.term) !bool {
    return c.aphid_closed((try get_database(database)).handle) != 0;
}
pub fn state(database: beam.term, session: u32) !i32 {
    return c.aphid_session_state((try get_database(database)).handle, session);
}
pub fn cancel(operation: beam.term) !bool {
    const op = try get_operation(operation);
    op.cancelled.store(true, .release);
    return c.aphid_cancel(op.parent.handle, op.session, op.id, 0) != 0;
}
pub fn finish(operation: beam.term) !bool {
    const op = try get_operation(operation);
    return c.aphid_finish(op.parent.handle, op.session, op.id) != 0;
}
pub fn operation_error(operation: beam.term) !beam.term {
    const op = try get_operation(operation);
    var err: c.aphid_error = undefined;
    if (c.aphid_operation_error(op.parent.handle, op.session, op.id, &err) == 0) return error.StaleOperation;
    return native_error(err);
}
pub fn transferring(operation: beam.term) !bool {
    const op = try get_operation(operation);
    return c.aphid_transferring(op.parent.handle, op.session, op.id) != 0;
}
pub fn stats() beam.term {
    return beam.make(.{ c.aphid_live_databases(), c.aphid_live_workers() }, .{});
}

pub fn collect(operation: beam.term, max_rows: u32, max_bytes: u64) !beam.term {
    beam.ignore_when_sema();
    const op = try get_operation(operation);
    var caller: e.ErlNifPid = undefined;
    _ = e.enif_self(beam.context.env, &caller);
    if (e.enif_compare(caller.pid, op.owner.pid) != 0) return error.ForeignOwner;
    return Result.collect(op.parent.handle, op.session, op.id, max_rows, max_bytes, &op.cancelled, false);
}
pub fn fetch(operation: beam.term, max_rows: u32, max_bytes: u64) !beam.term {
    beam.ignore_when_sema();
    const op = try get_operation(operation);
    var caller: e.ErlNifPid = undefined;
    _ = e.enif_self(beam.context.env, &caller);
    if (e.enif_compare(caller.pid, op.owner.pid) != 0) return error.ForeignOwner;
    return Result.collect(op.parent.handle, op.session, op.id, max_rows, max_bytes, &op.cancelled, true);
}

const Result = struct {
    const ConversionError = error{ PayloadLimit, InvalidList, InvalidType, InvalidText, UnsupportedType, DepthLimit, InvalidInteger, Nonfinite, InvalidValue, Cancelled };
    const Budget = struct {
        remaining: u64,
        cancelled: *const std.atomic.Value(bool),
        row: ?u64 = null,
        column: ?u64 = null,
        native_tag: u32 = 0,
        path: [33]u64 = undefined,
        path_len: usize = 0,
        fn charge(self: *Budget, amount: u64) !void {
            if (self.cancelled.load(.acquire)) return error.Cancelled;
            if (amount > self.remaining) return error.PayloadLimit;
            self.remaining -= amount;
        }
    };
    fn cons(head: beam.term, tail: beam.term) beam.term {
        return .{ .v = e.enif_make_list_cell(beam.context.env, head.v, tail.v) };
    }
    fn empty() beam.term {
        return .{ .v = e.enif_make_list_from_array(beam.context.env, null, 0) };
    }
    fn reverse(list: beam.term) !beam.term {
        var result: beam.term = undefined;
        if (e.enif_make_reverse_list(beam.context.env, list.v, &result.v) == 0) return error.InvalidList;
        return result;
    }
    fn item(tuple: beam.term, index: usize) !beam.term {
        var arity: c_int = undefined;
        var terms: [*c]const e.ERL_NIF_TERM = undefined;
        if (e.enif_get_tuple(beam.context.env, tuple.v, &arity, &terms) == 0 or index >= arity) return error.InvalidType;
        return .{ .v = terms[index] };
    }
    fn pop(list: *beam.term) !beam.term {
        var head: beam.term = undefined;
        if (e.enif_get_list_cell(beam.context.env, list.v, &head.v, &list.v) == 0) return error.InvalidType;
        return head;
    }
    fn bytes(view: c.aphid_bytes, text: bool, budget: *Budget) !beam.term {
        try budget.charge(view.length);
        const slice = view.data[0..view.length];
        if (text and !std.unicode.utf8ValidateSlice(slice)) return error.InvalidText;
        return beam.make(slice, .{});
    }
    fn tag(id: u32) !beam.term {
        return switch (id) {
            10 => beam.make(.node, .{}),
            11 => beam.make(.rel, .{}),
            12 => beam.make(.recursive_rel, .{}),
            13 => beam.make(.serial, .{}),
            22 => beam.make(.bool, .{}),
            23 => beam.make(.int64, .{}),
            24 => beam.make(.int32, .{}),
            25 => beam.make(.int16, .{}),
            26 => beam.make(.int8, .{}),
            27 => beam.make(.uint64, .{}),
            28 => beam.make(.uint32, .{}),
            29 => beam.make(.uint16, .{}),
            30 => beam.make(.uint8, .{}),
            31 => beam.make(.int128, .{}),
            32 => beam.make(.double, .{}),
            33 => beam.make(.float, .{}),
            34 => beam.make(.date, .{}),
            35 => beam.make(.timestamp, .{}),
            36 => beam.make(.timestamp_sec, .{}),
            37 => beam.make(.timestamp_ms, .{}),
            38 => beam.make(.timestamp_ns, .{}),
            39 => beam.make(.timestamp_tz, .{}),
            40 => beam.make(.interval, .{}),
            41 => beam.make(.decimal, .{}),
            42 => beam.make(.internal_id, .{}),
            43 => beam.make(.uint128, .{}),
            50 => beam.make(.string, .{}),
            51 => beam.make(.blob, .{}),
            52 => beam.make(.list, .{}),
            53 => beam.make(.array, .{}),
            54 => beam.make(.@"struct", .{}),
            55 => beam.make(.map, .{}),
            59 => beam.make(.uuid, .{}),
            60 => beam.make(.json, .{}),
            else => error.UnsupportedType,
        };
    }
    fn describe(cursor: *c.aphid_cursor, pointer: *const c.aphid_type, budget: *Budget, depth: u32) ConversionError!beam.term {
        if (depth > 32) return error.DepthLimit;
        budget.path_len = depth;
        try budget.charge(8);
        var info: c.aphid_type_info = undefined;
        var err: c.aphid_error = undefined;
        const status = c.aphid_type_inspect(pointer, &info, &err);
        budget.native_tag = info.tag;
        if (status != 0) return error.UnsupportedType;
        const atom = try tag(info.tag);
        if (info.tag == 41) return beam.make(.{ atom, info.aux1, info.aux2 }, .{});
        if (info.children == 0 and info.tag != 54 and info.tag != 10 and info.tag != 11 and info.tag != 12) return atom;
        var children = empty();
        var index: u64 = 0;
        while (index < info.children) : (index += 1) {
            var child: ?*const c.aphid_type = null;
            var name: c.aphid_bytes = undefined;
            if (c.aphid_type_child(cursor, pointer, index, &child, &name, &err) != 0) return error.InvalidType;
            const field_name = try bytes(name, true, budget); // Copy scratch bytes before recursion.
            budget.path[depth] = index;
            const child_type = try describe(cursor, child.?, budget, depth + 1);
            const field = if (info.tag == 54 or info.tag <= 12) beam.make(.{ field_name, child_type }, .{}) else child_type;
            children = cons(field, children);
        }
        children = try reverse(children);
        return switch (info.tag) {
            52 => beam.make(.{ atom, try pop(&children) }, .{}),
            53 => beam.make(.{ atom, try pop(&children), info.aux1 }, .{}),
            55 => blk: {
                const key = try pop(&children);
                break :blk beam.make(.{ atom, key, try pop(&children) }, .{});
            },
            else => beam.make(.{ atom, children }, .{}),
        };
    }
    fn integer(low: u64, high: u64, signed: bool) !beam.term {
        const bits = (@as(u128, high) << 64) | low;
        const negative = signed and (high >> 63 != 0);
        var magnitude = if (negative) (~bits) +% 1 else bits;
        // Standard Erlang SMALL_BIG_EXT, bounded to 128 bits; never a custom wire format.
        var encoded: [20]u8 = .{ 131, 110, 16, @intFromBool(negative) } ++ .{0} ** 16;
        for (encoded[4..]) |*digit| {
            digit.* = @truncate(magnitude);
            magnitude >>= 8;
        }
        var result: beam.term = undefined;
        if (e.enif_binary_to_term(beam.context.env, &encoded, encoded.len, &result.v, 0) != encoded.len) return error.InvalidInteger;
        return result;
    }
    fn wrapped(type_term: beam.term, value: beam.term) beam.term {
        return beam.make(.{ .__struct__ = .@"Elixir.Aphid.Value", .type = type_term, .value = value }, .{});
    }
    fn encode(pointer: *const c.aphid_value, type_term: beam.term, budget: *Budget, depth: u32) ConversionError!beam.term {
        if (depth > 32) return error.DepthLimit;
        budget.path_len = depth;
        var value: c.aphid_value_info = undefined;
        var info: c.aphid_type_info = undefined;
        var err: c.aphid_error = undefined;
        if (c.aphid_value_inspect(pointer, &value, &err) != 0) return error.UnsupportedType;
        if (c.aphid_type_inspect(value.type, &info, &err) != 0) return error.UnsupportedType;
        budget.native_tag = info.tag;
        try budget.charge(8);
        if (value.is_null != 0) return beam.make(.nil, .{});
        switch (info.tag) {
            22 => return beam.make(value.low != 0, .{}),
            13, 23...31, 43 => {
                try budget.charge(16);
                return integer(value.low, value.high, info.tag != 43 and (info.tag < 27 or info.tag > 30));
            },
            32, 33 => {
                try budget.charge(16);
                if (!std.math.isFinite(value.real)) return error.Nonfinite;
                return beam.make(value.real, .{});
            },
            34...39, 41 => {
                try budget.charge(16);
                return wrapped(type_term, try integer(value.low, value.high, true));
            },
            40 => {
                try budget.charge(24);
                return wrapped(type_term, beam.make(.{ value.months, value.days, @as(i64, @bitCast(value.low)) }, .{}));
            },
            42 => {
                try budget.charge(16);
                return wrapped(type_term, beam.make(.{ value.high, value.low }, .{}));
            },
            50, 51, 59, 60 => {
                const binary = try bytes(value.bytes, info.tag != 51, budget);
                return if (info.tag == 50) binary else wrapped(type_term, binary);
            },
            10...12, 52...55 => {
                var values = empty();
                var fields = if (info.tag <= 12 or info.tag == 54) try item(type_term, 1) else empty();
                var index: u64 = 0;
                while (index < value.children) : (index += 1) {
                    budget.path[depth] = index;
                    const child = c.aphid_value_child(pointer, index) orelse return error.InvalidValue;
                    var term: beam.term = undefined;
                    if (info.tag == 55) {
                        try budget.charge(8);
                        const key = c.aphid_value_child(child, 0) orelse return error.InvalidValue;
                        const val = c.aphid_value_child(child, 1) orelse return error.InvalidValue;
                        term = beam.make(.{ try encode(key, try item(type_term, 1), budget, depth + 1), try encode(val, try item(type_term, 2), budget, depth + 1) }, .{});
                    } else if (info.tag == 54 or info.tag <= 12) {
                        try budget.charge(8);
                        const field = try pop(&fields);
                        const name = try item(field, 0);
                        var binary: e.ErlNifBinary = undefined;
                        if (e.enif_inspect_binary(beam.context.env, name.v, &binary) == 0) return error.InvalidType;
                        try budget.charge(binary.size);
                        term = beam.make(.{ name, try encode(child, try item(field, 1), budget, depth + 1) }, .{});
                    } else {
                        term = try encode(child, try item(type_term, 1), budget, depth + 1);
                    }
                    values = cons(term, values);
                }
                values = try reverse(values);
                return if (info.tag == 55 or info.tag <= 12) wrapped(type_term, values) else values;
            },
            else => return error.UnsupportedType,
        }
    }

    pub fn collect(db: ?*c.aphid_db, session: u32, id: u64, max_rows: u32, max_bytes: u64, cancelled: *const std.atomic.Value(bool), batch: bool) beam.term {
        var budget = Budget{ .remaining = max_bytes, .cancelled = cancelled };
        return collect_result(db, session, id, max_rows, &budget, batch) catch |failure| {
            const code = switch (failure) {
                error.RowLimit => beam.make(.row_limit, .{}),
                error.RowTooLarge => beam.make(.row_too_large, .{}),
                error.PayloadLimit => beam.make(.payload_limit, .{}),
                error.DepthLimit => beam.make(.depth_limit, .{}),
                error.UnsupportedType => beam.make(.unsupported_type, .{}),
                error.InvalidLimit => beam.make(.invalid_option, .{}),
                error.ResultUnavailable => beam.make(.result_unavailable, .{}),
                error.Cancelled => beam.make(.cancelled, .{}),
                error.InvalidText, error.Nonfinite => beam.make(.invalid_value, .{}),
                else => beam.make(.native_error, .{}),
            };
            var path = empty();
            var index = budget.path_len;
            while (index > 0) {
                index -= 1;
                path = cons(beam.make(budget.path[index], .{}), path);
            }
            return beam.make(.{ .@"error", .{ .__struct__ = .@"Elixir.Aphid.Error", .__exception__ = true, .code = code, .message = @errorName(failure), .context = .{
                .row = budget.row,
                .column = budget.column,
                .path = path,
                .native_tag = budget.native_tag,
            } } }, .{});
        };
    }
    fn collect_result(db: ?*c.aphid_db, session: u32, id: u64, max_rows: u32, budget: *Budget, batch: bool) !beam.term {
        if (max_rows == 0 or budget.remaining == 0) return error.InvalidLimit;
        var err: c.aphid_error = undefined;
        const cursor = c.aphid_fetch_begin(db, session, id, &err) orelse return error.ResultUnavailable;
        defer if (!batch) { _ = c.aphid_finish(db, session, id); };
        errdefer if (batch) { _ = c.aphid_finish(db, session, id); };
        defer c.aphid_fetch_end(cursor);
        if (!batch and c.aphid_fetch_rows(cursor) > max_rows) return error.RowLimit;
        var columns = empty();
        var index: u64 = 0;
        const count = c.aphid_fetch_columns(cursor);
        while (index < count) : (index += 1) {
            budget.column = index;
            var name: c.aphid_bytes = undefined;
            var pointer: ?*const c.aphid_type = null;
            if (c.aphid_fetch_column(cursor, index, &name, &pointer) == 0) return error.InvalidColumn;
            const label = try bytes(name, true, budget);
            const type_term = try describe(cursor, pointer.?, budget, 0);
            columns = cons(beam.make(.{ label, type_term }, .{}), columns);
        }
        columns = try reverse(columns);
        var rows = empty();
        var row_index: u64 = 0;
        while (!batch or row_index < max_rows) {
            budget.row = c.aphid_fetch_position(cursor);
            const next = c.aphid_fetch_next(cursor, &err);
            if (next == 0) break;
            if (next < 0) return error.NativeFetch;
            budget.column = null;
            budget.path_len = 0;
            const row = encode_row(cursor, columns, count, budget) catch |failure| {
                if (batch and failure == error.PayloadLimit) {
                    if (row_index == 0) return error.RowTooLarge;
                    if (c.aphid_fetch_unread(cursor) == 0) return error.NativeFetch;
                    break;
                }
                return failure;
            };
            rows = cons(row, rows);
            row_index += 1;
        }
        const result = beam.make(.{ .__struct__ = .@"Elixir.Aphid.Result", .columns = columns, .rows = try reverse(rows), .statistics = .nil }, .{});
        if (!batch) return result;
        const done = c.aphid_fetch_position(cursor) == c.aphid_fetch_rows(cursor);
        if (done) _ = c.aphid_finish(db, session, id);
        return beam.make(.{ result, done }, .{});
    }
    fn encode_row(cursor: *c.aphid_cursor, columns: beam.term, count: u64, budget: *Budget) !beam.term {
        try budget.charge(8);
        var row = empty();
        var remaining_columns = columns;
        var index: u64 = 0;
        while (index < count) : (index += 1) {
            budget.column = index;
            const column = try pop(&remaining_columns);
            const pointer = c.aphid_fetch_value(cursor, index) orelse return error.InvalidValue;
            row = cons(try encode(pointer, try item(column, 1), budget, 0), row);
        }
        return reverse(row);
    }
};

const Input = struct {
    const Errors = error{ Cancelled, ParameterLimit, InvalidValue, ExpectedBinary, InputTooLarge, InvalidText, ExplicitTypeRequired, MixedTypes, DepthLimit, InvalidType, UnsupportedType, UnsupportedInputType, OutOfMemory, InvalidList, IntegerOverflow, ExpectedInteger, InvalidInteger, InvalidBoolean, ExpectedFloat, Nonfinite, InvalidInterval, TypeMismatch };
    cancelled: *const std.atomic.Value(bool),
    remaining: usize = 1024 * 1024,
    parameter: beam.term = undefined,
    native_error_info: c.aphid_error = std.mem.zeroes(c.aphid_error),
    path: [33]u64 = undefined,
    path_len: usize = 0,
    inferred_nodes: usize = 0,

    fn charge(self: *Input, amount: usize) !void {
        if (self.cancelled.load(.acquire)) return error.Cancelled;
        if (amount > self.remaining) return error.ParameterLimit;
        self.remaining -= amount;
    }
    fn equal(left: beam.term, right: beam.term) bool {
        return e.enif_is_identical(left.v, right.v) != 0;
    }
    fn field(term: beam.term, comptime name: anytype) !beam.term {
        var output: beam.term = undefined;
        if (e.enif_get_map_value(beam.context.env, term.v, beam.make(name, .{}).v, &output.v) == 0) return error.InvalidValue;
        return output;
    }
    fn binary(self: *Input, term: beam.term, text: bool) ![]const u8 {
        const data = try get_binary(term, self.remaining);
        try self.charge(data.len);
        if (text and !std.unicode.utf8ValidateSlice(data)) return error.InvalidText;
        return data;
    }
    fn wrapper(term: beam.term) !?beam.term {
        if (e.enif_is_map(beam.context.env, term.v) == 0) return null;
        var count: usize = undefined;
        if (e.enif_get_map_size(beam.context.env, term.v, &count) == 0 or count != 3) return error.InvalidValue;
        if (!equal(try field(term, .__struct__), beam.make(.@"Elixir.Aphid.Value", .{}))) return error.InvalidValue;
        return try field(term, .type);
    }
    fn parts(term: beam.term, expected: c_int) ![*c]const e.ERL_NIF_TERM {
        var arity: c_int = undefined;
        var tuple: [*c]const e.ERL_NIF_TERM = undefined;
        if (e.enif_get_tuple(beam.context.env, term.v, &arity, &tuple) == 0 or arity != expected) return error.InvalidType;
        return tuple;
    }
    fn length(self: *Input, term: beam.term) !usize {
        var list = term;
        var count: usize = 0;
        while (!equal(list, Result.empty())) {
            try self.charge(0);
            if (count >= self.remaining / 8) return error.ParameterLimit;
            _ = try Result.pop(&list);
            count += 1;
        }
        return count;
    }
    fn infer(self: *Input, term: beam.term, depth: u32) Errors!beam.term {
        if (depth > 32) return error.DepthLimit;
        self.path_len = depth;
        try self.charge(0);
        self.inferred_nodes += 1;
        if (self.inferred_nodes > 131072) return error.ParameterLimit;
        if (try wrapper(term)) |type_term| return type_term;
        if (equal(term, beam.make(true, .{})) or equal(term, beam.make(false, .{}))) return beam.make(.bool, .{});
        var number: i64 = undefined;
        if (e.enif_get_int64(beam.context.env, term.v, &number) != 0) return beam.make(.int64, .{});
        var float: f64 = undefined;
        if (e.enif_get_double(beam.context.env, term.v, &float) != 0) return beam.make(.double, .{});
        var buffer: e.ErlNifBinary = undefined;
        if (e.enif_inspect_binary(beam.context.env, term.v, &buffer) != 0) return beam.make(.string, .{});
        var head: e.ERL_NIF_TERM = undefined;
        var tail: e.ERL_NIF_TERM = undefined;
        if (equal(term, Result.empty()) or e.enif_get_list_cell(beam.context.env, term.v, &head, &tail) != 0) {
            var list = term;
            var child_type: ?beam.term = null;
            var index: u64 = 0;
            while (!equal(list, Result.empty())) : (index += 1) {
                try self.charge(0);
                if (index >= self.remaining / 8) return error.ParameterLimit;
                const child = try Result.pop(&list);
                self.path[depth] = index;
                if (equal(child, beam.make(.nil, .{}))) continue;
                const candidate = try self.infer(child, depth + 1);
                if (child_type) |expected| {
                    if (!equal(expected, candidate)) return error.MixedTypes;
                } else child_type = candidate;
            }
            return beam.make(.{ .list, child_type orelse return error.ExplicitTypeRequired }, .{});
        }
        return error.ExplicitTypeRequired;
    }
    fn integer(term: beam.term, unsigned: bool, scalar: *c.aphid_value_info) !void {
        var signed: i64 = undefined;
        if (e.enif_get_int64(beam.context.env, term.v, &signed) != 0) {
            if (unsigned and signed < 0) return error.IntegerOverflow;
            scalar.low = @bitCast(signed);
            scalar.high = if (signed < 0) std.math.maxInt(u64) else 0;
            return;
        }
        if (e.enif_get_uint64(beam.context.env, term.v, &scalar.low) != 0) return;
        var float: f64 = undefined;
        if (e.enif_is_number(beam.context.env, term.v) == 0 or e.enif_get_double(beam.context.env, term.v, &float) != 0) return error.ExpectedInteger;
        const minimum = try Result.integer(0, if (unsigned) 0 else 0x8000000000000000, !unsigned);
        const maximum = try Result.integer(std.math.maxInt(u64), if (unsigned) std.math.maxInt(u64) else 0x7fffffffffffffff, !unsigned);
        if (e.enif_compare(term.v, minimum.v) < 0 or e.enif_compare(term.v, maximum.v) > 0) return error.IntegerOverflow;
        // Range-check before serialization: the standard ETF encoding is at most 20 bytes.
        var buffer: e.ErlNifBinary = undefined;
        if (e.enif_term_to_binary(beam.context.env, term.v, &buffer) == 0) return error.OutOfMemory;
        defer e.enif_release_binary(&buffer);
        if (buffer.size < 4 or buffer.size > 20 or buffer.data[1] != 110 or buffer.data[2] > 16) return error.InvalidInteger;
        var magnitude: u128 = 0;
        for (buffer.data[4..buffer.size], 0..) |digit, index| magnitude |= @as(u128, digit) << @intCast(index * 8);
        if (buffer.data[3] != 0) magnitude = (~magnitude) +% 1;
        scalar.low = @truncate(magnitude);
        scalar.high = @truncate(magnitude >> 64);
    }
    fn value(self: *Input, input: beam.term) !*c.aphid_value {
        self.inferred_nodes = 0;
        const type_term = try self.infer(input, 0);
        const pointer = try self.make_type(type_term, 0);
        defer c.aphid_type_free(pointer);
        return self.encode(type_term, pointer, input, 0);
    }
    fn make_type(self: *Input, type_term: beam.term, depth: u32) Errors!*c.aphid_type {
        if (depth > 32) return error.DepthLimit;
        self.path_len = depth;
        try self.charge(8);
        var tag: u32 = 0;
        var aux1: u64 = 0;
        var aux2: u64 = 0;
        var arity: c_int = undefined;
        var tuple: [*c]const e.ERL_NIF_TERM = undefined;
        var count: usize = 0;
        var fields = Result.empty();
        if (e.enif_get_tuple(beam.context.env, type_term.v, &arity, &tuple) != 0) {
            if (arity < 2) return error.InvalidType;
            const kind = beam.term{ .v = tuple[0] };
            if (equal(kind, beam.make(.decimal, .{}))) {
                if (arity != 3 or e.enif_get_uint64(beam.context.env, tuple[1], &aux1) == 0 or e.enif_get_uint64(beam.context.env, tuple[2], &aux2) == 0) return error.InvalidType;
                tag = 41;
            } else if (equal(kind, beam.make(.list, .{}))) {
                if (arity != 2) return error.InvalidType;
                tag = 52;
                count = 1;
            } else if (equal(kind, beam.make(.array, .{}))) {
                if (arity != 3 or e.enif_get_uint64(beam.context.env, tuple[2], &aux1) == 0) return error.InvalidType;
                tag = 53;
                count = 1;
            } else if (equal(kind, beam.make(.map, .{}))) {
                if (arity != 3) return error.InvalidType;
                tag = 55;
                count = 2;
            } else if (equal(kind, beam.make(.@"struct", .{}))) {
                if (arity != 2) return error.InvalidType;
                tag = 54;
                fields = .{ .v = tuple[1] };
                count = try self.length(fields);
            } else return error.UnsupportedInputType;
        } else {
            for ([_]u32{ 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 43, 50, 51, 59, 60 }) |candidate| {
                if (equal(type_term, try Result.tag(candidate))) {
                    tag = candidate;
                    break;
                }
            }
            if (tag == 0) return error.UnsupportedInputType;
        }
        const children = try beam.allocator.alloc(?*const c.aphid_type, count);
        @memset(children, null);
        defer {
            for (children) |child| if (child) |pointer| {
                c.aphid_type_free(@constCast(pointer));
            };
            beam.allocator.free(children);
        }
        const names = try beam.allocator.alloc(c.aphid_bytes, count);
        defer beam.allocator.free(names);
        for (children, 0..) |*child, index| {
            self.path[depth] = index;
            self.path_len = depth + 1;
            var descriptor: beam.term = undefined;
            names[index] = std.mem.zeroes(c.aphid_bytes);
            if (tag == 54) {
                const pair = try parts(try Result.pop(&fields), 2);
                const name = try self.binary(.{ .v = pair[0] }, true);
                names[index] = .{ .data = name.ptr, .length = name.len };
                descriptor = .{ .v = pair[1] };
            } else descriptor = .{ .v = tuple[index + 1] };
            child.* = try self.make_type(descriptor, depth + 1);
        }
        return c.aphid_type_make(tag, aux1, aux2, children.ptr, names.ptr, count, &self.native_error_info) orelse error.InvalidType;
    }
    fn encode(self: *Input, type_term: beam.term, type_pointer: *const c.aphid_type, input: beam.term, depth: u32) Errors!*c.aphid_value {
        if (depth > 32) return error.DepthLimit;
        self.path_len = depth;
        try self.charge(8);
        var raw = input;
        if (try wrapper(input)) |explicit| {
            if (!equal(explicit, type_term)) return error.TypeMismatch;
            raw = try field(input, .value);
        }
        var info: c.aphid_type_info = undefined;
        if (c.aphid_type_inspect(type_pointer, &info, &self.native_error_info) != 0) return error.InvalidType;
        const tag = info.tag;
        var arity: c_int = undefined;
        var tuple: [*c]const e.ERL_NIF_TERM = undefined;
        var scalar = std.mem.zeroes(c.aphid_value_info);
        scalar.is_null = @intFromBool(equal(raw, beam.make(.nil, .{})));
        if (scalar.is_null == 0 and tag >= 52 and tag <= 55) {
            const count = try self.length(raw);
            if ((tag == 53 and count != info.aux1) or (tag == 54 and count != info.children)) return error.TypeMismatch;
            const children = try beam.allocator.alloc(?*c.aphid_value, count * @as(usize, if (tag == 55) 2 else 1));
            @memset(children, null);
            defer {
                for (children) |child| c.aphid_value_free(child);
                beam.allocator.free(children);
            }
            var items = raw;
            var fields = if (tag == 54) try Result.item(type_term, 1) else Result.empty();
            for (0..count) |index| {
                self.path[depth] = index;
                self.path_len = depth + 1;
                const entry = try Result.pop(&items);
                var field_type: beam.term = undefined;
                var child_input = entry;
                if (tag == 54) {
                    try self.charge(8);
                    const expected = try parts(try Result.pop(&fields), 2);
                    const actual = try parts(entry, 2);
                    if (!equal(.{ .v = expected[0] }, .{ .v = actual[0] })) return error.TypeMismatch;
                    _ = try self.binary(.{ .v = actual[0] }, true);
                    field_type = .{ .v = expected[1] };
                    child_input = .{ .v = actual[1] };
                } else field_type = try Result.item(type_term, 1);
                var child_pointer: ?*const c.aphid_type = null;
                var unused_name: c.aphid_bytes = undefined;
                if (c.aphid_type_child(null, type_pointer, if (tag == 54) index else 0, &child_pointer, &unused_name, &self.native_error_info) != 0) return error.InvalidType;
                if (tag == 55) {
                    try self.charge(8);
                    const pair = try parts(entry, 2);
                    children[index * 2] = try self.encode(field_type, child_pointer.?, .{ .v = pair[0] }, depth + 1);
                    if (c.aphid_type_child(null, type_pointer, 1, &child_pointer, &unused_name, &self.native_error_info) != 0) return error.InvalidType;
                    children[index * 2 + 1] = try self.encode(try Result.item(type_term, 2), child_pointer.?, .{ .v = pair[1] }, depth + 1);
                } else children[index] = try self.encode(field_type, child_pointer.?, child_input, depth + 1);
            }
            return c.aphid_value_make(type_pointer, &scalar, children.ptr, children.len, &self.native_error_info) orelse error.InvalidValue;
        }
        if (scalar.is_null == 0) switch (tag) {
            22 => {
                if (!equal(raw, beam.make(true, .{})) and !equal(raw, beam.make(false, .{}))) return error.InvalidBoolean;
                scalar.low = @intFromBool(equal(raw, beam.make(true, .{})));
            },
            32, 33 => {
                try self.charge(16);
                if (e.enif_get_double(beam.context.env, raw.v, &scalar.real) == 0) return error.ExpectedFloat;
                if (!std.math.isFinite(scalar.real)) return error.Nonfinite;
            },
            50, 51, 59, 60 => {
                const data = try self.binary(raw, tag != 51);
                scalar.bytes = .{ .data = data.ptr, .length = data.len };
            },
            40 => {
                try self.charge(24);
                if (e.enif_get_tuple(beam.context.env, raw.v, &arity, &tuple) == 0 or arity != 3) return error.InvalidInterval;
                if (e.enif_get_int(beam.context.env, tuple[0], &scalar.months) == 0 or e.enif_get_int(beam.context.env, tuple[1], &scalar.days) == 0) return error.InvalidInterval;
                try integer(.{ .v = tuple[2] }, false, &scalar);
            },
            else => {
                try self.charge(16);
                try integer(raw, (tag >= 27 and tag <= 30) or tag == 43, &scalar);
            },
        };
        return c.aphid_value_make(type_pointer, &scalar, null, 0, &self.native_error_info) orelse error.InvalidValue;
    }
    fn convert(self: *Input, parameters: beam.term) !*c.aphid_params {
        var count: usize = undefined;
        if (e.enif_get_map_size(beam.context.env, parameters.v, &count) == 0) return error.ExpectedParameterMap;
        if (count > self.remaining / 16) return error.ParameterLimit;
        const params = c.aphid_params_new(&self.native_error_info) orelse return error.OutOfMemory;
        errdefer c.aphid_params_free(params);
        var iterator: e.ErlNifMapIterator = undefined;
        if (e.enif_map_iterator_create(beam.context.env, parameters.v, &iterator, e.ERL_NIF_MAP_ITERATOR_FIRST) == 0) return error.InvalidParameters;
        defer e.enif_map_iterator_destroy(beam.context.env, &iterator);
        var key: beam.term = undefined;
        var term: beam.term = undefined;
        while (e.enif_map_iterator_get_pair(beam.context.env, &iterator, &key.v, &term.v) != 0) {
            self.parameter = key;
            self.path_len = 0;
            const name = try self.binary(key, true);
            if (name.len == 0 or name[0] == '$') return error.InvalidParameterName;
            const converted = try self.value(term);
            if (c.aphid_params_add(params, .{ .data = name.ptr, .length = name.len }, converted, &self.native_error_info) != 0) return error.InvalidValue;
            _ = e.enif_map_iterator_next(beam.context.env, &iterator);
        }
        return params;
    }
    fn failure(self: *Input, err: anytype) beam.term {
        const message: []const u8 = if (self.native_error_info.length == 0) @errorName(err) else @as([*]const u8, @ptrCast(&self.native_error_info.message))[0..self.native_error_info.length];
        var path = Result.empty();
        var index = self.path_len;
        while (index > 0) {
            index -= 1;
            path = Result.cons(beam.make(self.path[index], .{}), path);
        }
        const code = switch (err) {
            error.ParameterLimit, error.InputTooLarge => beam.make(.parameter_limit, .{}),
            error.Cancelled => beam.make(.cancelled, .{}),
            else => beam.make(.invalid_parameter, .{}),
        };
        return beam.make(.{ .@"error", .{ .__struct__ = .@"Elixir.Aphid.Error", .__exception__ = true, .code = code, .message = message, .context = .{ .parameter = self.parameter, .path = path } } }, .{});
    }
};
