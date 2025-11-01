pub const packages = struct {
    pub const @"/p/zio-0.4.0-xHbVVCDyGgCLDUGXDdbugnE8I7dbNkTungdjWQGIIOqq/vendor/libxev" = struct {
        pub const build_root = "/Users/rand/.cache/zig/p/zio-0.4.0-xHbVVCDyGgCLDUGXDdbugnE8I7dbNkTungdjWQGIIOqq/vendor/libxev";
        pub const build_zig = @import("/p/zio-0.4.0-xHbVVCDyGgCLDUGXDdbugnE8I7dbNkTungdjWQGIIOqq/vendor/libxev");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
    pub const @"zio-0.4.0-xHbVVCDyGgCLDUGXDdbugnE8I7dbNkTungdjWQGIIOqq" = struct {
        pub const build_root = "/Users/rand/.cache/zig/p/zio-0.4.0-xHbVVCDyGgCLDUGXDdbugnE8I7dbNkTungdjWQGIIOqq";
        pub const build_zig = @import("zio-0.4.0-xHbVVCDyGgCLDUGXDdbugnE8I7dbNkTungdjWQGIIOqq");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
            .{ "libxev", "/p/zio-0.4.0-xHbVVCDyGgCLDUGXDdbugnE8I7dbNkTungdjWQGIIOqq/vendor/libxev" },
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "zio", "zio-0.4.0-xHbVVCDyGgCLDUGXDdbugnE8I7dbNkTungdjWQGIIOqq" },
};
