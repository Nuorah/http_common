const std = @import("std");
const http = std.http;

pub fn Route(comptime Context: type) type {
    return struct {
        method: http.Method,
        path: []const u8,
        handler: *const fn (
            std.mem.Allocator,
            std.mem.Allocator,
            *Context,
            *http.Server.Request,
            std.StringHashMap([]const u8),
            std.StringHashMap([]const u8),
        ) anyerror!void,
        match: enum { exact, prefix, pattern } = .exact,
    };
}

pub fn Router(comptime context: type, comptime routes: []const Route(context)) type {
    return struct {
        pub fn route(
            main_allocator: std.mem.Allocator,
            arena: std.mem.Allocator,
            ctx: *context,
            request: *http.Server.Request,
        ) !void {
            const split = splitPathQuery(request.head.target);
            inline for (routes) |r| {
                if (r.method == request.head.method) {
                    var path_params = std.StringHashMap([]const u8).init(arena);
                    var query_params = std.StringHashMap([]const u8).init(arena);

                    if (split.query) |query| {
                        try parseQueryString(query, &query_params);
                    }
                    const matches = switch (r.match) {
                        .exact => std.mem.eql(u8, r.path, request.head.target),
                        .prefix => std.mem.startsWith(u8, request.head.target, r.path),
                        .pattern => try matchPattern(r.path, split.path, &path_params),
                    };

                    if (matches) {
                        return r.handler(main_allocator, arena, ctx, request, path_params, query_params);
                    }
                }
            }
            try request.respond("Not found.", .{ .status = .not_found });
        }
    };
}

fn isParam(segment: []const u8) bool {
    return segment.len > 0 and segment[0] == ':';
}

fn splitPathQuery(target: []const u8) struct { path: []const u8, query: ?[]const u8 } {
    if (std.mem.indexOfScalar(u8, target, '?')) |idx| {
        return .{
            .path = target[0..idx],
            .query = target[idx + 1 ..],
        };
    }
    return .{
        .path = target,
        .query = null,
    };
}

fn parseQueryString(query: []const u8, params: *std.StringHashMap([]const u8)) !void {
    var pairs = std.mem.splitScalar(u8, query, '&');
    while (pairs.next()) |pair| {
        if (pair.len == 0) continue;
        if (std.mem.indexOfScalar(u8, pair, '=')) |eq_idx| {
            const key = pair[0..eq_idx];
            const value = pair[eq_idx + 1 ..];
            try params.put(key, value);
        } else {
            try params.put(pair, "");
        }
    }
}

fn matchPattern(pattern: []const u8, path: []const u8, params: *std.StringHashMap([]const u8)) !bool {
    var pattern_it = std.mem.splitScalar(u8, pattern, '/');
    var path_it = std.mem.splitScalar(u8, path, '/');

    while (pattern_it.next()) |pattern_seg| {
        const path_seg = path_it.next() orelse return false;

        if (isParam(pattern_seg)) {
            const param_name = pattern_seg[1..];
            try params.put(param_name, path_seg);
        } else {
            if (!std.mem.eql(u8, pattern_seg, path_seg)) {
                return false;
            }
        }
    }

    if (path_it.next() != null) return false;

    return true;
}
