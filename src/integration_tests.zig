const std = @import("std");
const testing = std.testing;
const http = std.http;
const server = @import("server.zig");
const router = @import("router.zig");
const helpers = @import("test_helpers.zig");
const Route = router.Route;

fn handle(_: std.mem.Allocator, req: *http.Server.Request) !void {
    try req.respond("Hello, World!", .{});
}

const routes = [_]Route{
    .{ .method = .GET, .path = "/", .handler = handle },
};

const TestRouter = router.Router(&routes);

test "server handles basic GET request" {
    const allocator = testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var shutdown = std.atomic.Value(bool).init(false);

    var testServer = try helpers.TestServer.start(arena.allocator(), 9876, TestRouter.route, &shutdown);
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

    var shutdown = std.atomic.Value(bool).init(false);

    var testServer = try helpers.TestServer.start(arena.allocator(), 9876, TestRouter.route, &shutdown);
    defer {
        testServer.stop();
    }

    const result = try helpers.makeRequest(allocator, 9876, "/doesntExist", .GET);

    // Check status
    try testing.expectEqual(.not_found, result.response.head.status);

    defer allocator.free(result.body);

    try testing.expectEqualStrings("Not found.", result.body);
}
