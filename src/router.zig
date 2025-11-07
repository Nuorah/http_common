const std = @import("std");
const http = std.http;

pub fn Route(comptime Context: type) type {
    return struct {
        method: http.Method,
        path: []const u8,
        handler: *const fn (std.mem.Allocator, std.mem.Allocator, *Context, *http.Server.Request) anyerror!void,
        match: enum { exact, prefix } = .exact,
    };
}
pub fn Router(comptime context: type, comptime routes: []const Route(context)) type {
    return struct {
        pub fn route(main_allocator: std.mem.Allocator, arena: std.mem.Allocator, ctx: *context, request: *http.Server.Request) !void {
            inline for (routes) |r| {
                if (r.method == request.head.method) {
                    const matches = switch (r.match) {
                        .exact => std.mem.eql(u8, r.path, request.head.target),
                        .prefix => std.mem.startsWith(u8, request.head.target, r.path),
                    };

                    if (matches) {
                        return r.handler(main_allocator, arena, ctx, request);
                    }
                }
            }
            try request.respond("Not found.", .{ .status = .not_found });
        }
    };
}
