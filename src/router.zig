const std = @import("std");
const http = std.http;

pub const Route = struct {
    method: http.Method,
    path: []const u8,
    handler: *const fn (std.mem.Allocator, *http.Server.Request) anyerror!void,
    match: enum { exact, prefix },
};

pub fn Router(comptime routes: []const Route) type {
    return struct {
        pub fn route(allocator: std.mem.Allocator, request: *http.Server.Request) !void {
            inline for (routes) |r| {
                if (r.method != request.head.method) continue;

                const matches = switch (r.match) {
                    .exact => std.mem.eql(u8, r.path, request.head.target),
                    .prefix => std.mem.eql(u8, r.path, request.head.target),
                };

                if (matches) {
                    return r.handler(allocator, request);
                }
            }

            try request.respond("Not found.", .{ .status = .not_found });
        }
    };
}
