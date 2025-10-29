const build_options = @import("build_options");

pub const std_options = .{
    .log_level = build_options.log_level,
};

pub const Server = @import("server.zig");
pub const Router = @import("router.zig");
