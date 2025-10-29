const std = @import("std");
const server = @import("server.zig");

pub const TestServer = struct {
    thread: std.Thread,
    shutdown: *std.atomic.Value(bool),
    port: u16,

    pub fn start(allocator: std.mem.Allocator, port: u16, handler: server.RequestRouter, shutdown: *std.atomic.Value(bool)) !TestServer {
        var self = TestServer{
            .thread = undefined,
            .shutdown = shutdown,
            .port = port,
        };

        const config = server.ServerConfiguration{ .port = port };
        self.thread = try std.Thread.spawn(.{}, server.runServer, .{
            allocator,
            config,
            handler,
            self.shutdown,
        });

        std.Thread.sleep(10 * std.time.ns_per_ms);

        return self;
    }

    pub fn stop(self: *TestServer) void {
        std.debug.print("Stop server thread\n", .{});
        self.shutdown.store(true, .release);
        self.thread.join();
    }
};

pub fn makeRequest(allocator: std.mem.Allocator, port: u16, path: []const u8, method: std.http.Method) !struct {
    body: []u8,
    response: std.http.Client.Response,
} {
    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const uri_str = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}{s}", .{ port, path });
    defer allocator.free(uri_str);

    const uri = try std.Uri.parse(uri_str);
    var req = try client.request(method, uri, .{});
    defer req.deinit();

    try req.sendBodiless();

    var redirect_buffer: [1024]u8 = undefined;
    var response: std.http.Client.Response = try req.receiveHead(&redirect_buffer);

    var transfer_buffer: [64]u8 = undefined;
    var reader = response.reader(&transfer_buffer);

    const body = try reader.allocRemaining(allocator, .unlimited);

    return .{ .response = response, .body = body };
}
