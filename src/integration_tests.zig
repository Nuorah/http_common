const std = @import("std");
const testing = std.testing;
const http = std.http;
const server = @import("server.zig");
const router = @import("router.zig");
const helpers = @import("test_helpers.zig");
const Route = router.Route;

const Context = struct {};

fn handle(
    _: std.mem.Allocator,
    _: std.mem.Allocator,
    _: *Context,
    _: *http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !router.Response {
    return router.Response{
        .body = "Hello, World!",
        .status = .ok,
    };
}

const routes = [_]Route(Context){
    .{ .method = .GET, .path = "/", .handler = handle },
};

const TestRouter = router.Router(Context, &routes);

test "server handles basic GET request" {
    var allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var ctx = Context{};
    var shutdown = std.atomic.Value(bool).init(false);

    const TestServer = helpers.TestServer(Context);
    var testServer = try TestServer.start(arena.allocator(), 9876, &ctx, &TestRouter.route, &shutdown);
    defer {
        testServer.stop();
    }

    const result = try helpers.makeRequest(allocator, 9876, "/", .GET);
    defer allocator.free(result.body);

    // Check status
    try testing.expectEqual(.ok, result.response.head.status);

    try testing.expectEqualStrings("Hello, World!", result.body);

    const result2 = try helpers.makeRequest(allocator, 9876, "/", .GET);
    defer allocator.free(result2.body);

    // Check status
    try testing.expectEqual(.ok, result2.response.head.status);

    try testing.expectEqualStrings("Hello, World!", result2.body);
}

test "server handles basic GET request 404" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var ctx = Context{};
    var shutdown = std.atomic.Value(bool).init(false);

    const TestServer = helpers.TestServer(Context);
    var testServer = try TestServer.start(arena.allocator(), 9876, &ctx, TestRouter.route, &shutdown);
    defer {
        testServer.stop();
    }

    const result = try helpers.makeRequest(allocator, 9876, "/doesntExist", .GET);

    // Check status
    try testing.expectEqual(.not_found, result.response.head.status);

    defer allocator.free(result.body);

    try testing.expectEqualStrings("Not found.", result.body);
}
