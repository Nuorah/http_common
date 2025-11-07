const std = @import("std");
const net = std.net;
const http = std.http;
const router_lib = @import("router.zig");

pub const ServerConfiguration = struct {
    address: []const u8 = "127.0.0.1",
    port: u16,
    thread_multiplier: usize = 2,
};

pub fn RequestRouter(comptime Context: type) type {
    return *const fn (
        std.mem.Allocator,
        std.mem.Allocator,
        *Context,
        *http.Server.Request,
    ) anyerror!void;
}

pub fn WorkerThread(comptime Context: type) type {
    return struct {
        pub fn run(
            thread_id: usize,
            main_allocator: std.mem.Allocator,
            listener: *net.Server,
            context: *Context,
            router: RequestRouter(Context),
            shutdown: *const std.atomic.Value(bool),
        ) !void {
            var arena_allocator = std.heap.ArenaAllocator.init(main_allocator);
            defer arena_allocator.deinit();

            std.log.debug("Thread {} reporting for duty\n", .{thread_id});

            while (!shutdown.load(.acquire)) {
                const connection = listener.accept() catch |err| switch (err) {
                    error.WouldBlock => continue,
                    else => {
                        std.log.err("Thread {}: Accept failed: {}", .{ thread_id, err });
                        continue;
                    },
                };
                defer connection.stream.close();

                const connection_timeout = std.posix.timeval{ .sec = 180, .usec = 0 };
                std.posix.setsockopt(
                    connection.stream.handle,
                    std.posix.SOL.SOCKET,
                    std.posix.SO.RCVTIMEO,
                    std.mem.asBytes(&connection_timeout),
                ) catch |err| {
                    std.log.err("Thread {}: Failed to clear timeout: {}", .{ thread_id, err });
                    continue;
                };

                handleConnection(Context, main_allocator, &arena_allocator, connection.stream, context, router, shutdown) catch |err| {
                    std.log.err("Thread {}: Connection failed {}", .{ thread_id, err });
                };
            }
        }
    };
}

pub fn runServer(
    comptime Context: type,
    allocator: std.mem.Allocator,
    config: ServerConfiguration,
    context: *Context,
    router: RequestRouter(Context),
    shutdown: *const std.atomic.Value(bool),
) !void {
    const address = try net.Address.parseIp(config.address, config.port);
    var listener = try address.listen(.{
        .reuse_address = true,
        .kernel_backlog = 4096,
    });
    defer listener.stream.close();

    const timeout = std.posix.timeval{
        .sec = 1,
        .usec = 0,
    };
    try std.posix.setsockopt(
        listener.stream.handle,
        std.posix.SOL.SOCKET,
        std.posix.SO.RCVTIMEO,
        std.mem.asBytes(&timeout),
    );

    const thread_count = @max(1, try std.Thread.getCpuCount() * config.thread_multiplier);

    std.log.info("Spinning up {d} worker threads", .{thread_count});
    std.log.info("listening on http://{s}:{d}", .{ config.address, config.port });

    const threads = try allocator.alloc(std.Thread, thread_count);
    defer allocator.free(threads);

    const Worker = WorkerThread(Context);

    for (threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(
            .{},
            Worker.run,
            .{ i, allocator, &listener, context, router, shutdown },
        );
    }

    for (threads) |thread| {
        thread.join();
    }
}

fn handleConnection(
    comptime Context: type,
    main_allocator: std.mem.Allocator,
    arena: *std.heap.ArenaAllocator,
    stream: net.Stream,
    context: *Context,
    router: RequestRouter(Context),
    shutdown: *const std.atomic.Value(bool),
) !void {
    var in_buf: [2048]u8 = undefined;
    var out_buf: [1024]u8 = undefined;

    var reader = stream.reader(&in_buf);
    var writer = stream.writer(&out_buf);

    var server = http.Server.init(reader.interface(), &writer.interface);

    while (!shutdown.load(.acquire)) {
        var request = server.receiveHead() catch |err| {
            switch (err) {
                error.HttpConnectionClosing => break,
                else => {
                    std.log.err("Error while receiving head: {}", .{err});
                    return err;
                },
            }
        };

        try router(main_allocator, arena.allocator(), context, &request);
        _ = arena.reset(.{ .retain_with_limit = 32 * 1024 });

        if (!request.head.keep_alive) break;
    }
}
