# Http common
Simple http library written in zig, with the stdlib http as a base. Intended for my personal use, but if you like it, use it!

Right now it's multithreaded with a fixed thread pool and one arena allocator per thread. You define routes with a
comptime array and you can pass a context object with a custom type.

# Quick start
1. Add the dependency in build.zig.zon and build.zig
2. Import `http_common = @import("http_common")`
3. Basic server:
```
  pub const config: http_common.server.ServerConfiguration = .{
    .port = 8080,
  };

  const Context = struct.{};

  const routes = [_]http_common.router.Route(Context){
    .{ .method = .GET, .path = "/", .handler = handleHome },
  };

  const app_router = router.Router(Context, &routes);

  pub fn main() !void {
    const main_allocator = std.heap.c_allocator // /!\ Needs a thread-safe allocator!
    var context: Context = .{};
    var shutdown = std.atomic.Value(bool).init(false) // For safe shutdown

    try server.runServer(Context, main_allocator, config, &context, app_router.route, &shutdown)
  }

  pub fn handleHome(_: std.mem.Allocator, _: *Context, req: *http.Server.Request) !void {
    try req.respond("Hello world!", .{});
  }
````

