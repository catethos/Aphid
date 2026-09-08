const beam = @import("beam");
const root = @import("root");
const c = @import("bridge");
const std = @import("std");

var live = std.atomic.Value(u32).init(0);
const Callbacks = struct {
    pub fn dtor(_: *u32) void {
        _ = live.fetchSub(1, .monotonic);
    }
};
pub const Token = beam.Resource(u32, root, .{ .Callbacks = Callbacks });

pub fn abi_version() u32 { return c.aphid_abi_version(); }
pub fn add(a: i32, b: i32) i64 { return c.aphid_proof_add(a, b); }
pub fn token() !Token {
    const resource = try Token.create(1, .{});
    _ = live.fetchAdd(1, .monotonic);
    return resource;
}
pub fn token_value(resource: Token) u32 { return resource.unpack(); }
pub fn live_tokens() u32 { return live.load(.monotonic); }
