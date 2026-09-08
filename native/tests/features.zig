const c = @import("features");
pub fn check(reopen: bool, graph: []const u8, fixture: []const u8) i32 {
    return c.aphid_features(@intFromBool(reopen), graph.ptr, graph.len, fixture.ptr, fixture.len);
}
