const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Standard target options allow the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});
    // It's also possible to define more custom flags to toggle optional features
    // of this build script using `b.option()`. All defined flags (including
    // target and optimize options) will be listed when running `zig build --help`
    // in this directory.

    // Optional tree-sitter support (for syntax highlighting)
    // Defaults to true for backward compatibility, but can be disabled for CI or
    // environments where tree-sitter libraries are not available
    const enable_treesitter = b.option(bool, "enable-treesitter", "Enable tree-sitter syntax highlighting support (default: true)") orelse true;

    // This creates a module, which represents a collection of source files alongside
    // some compilation options, such as optimization mode and linked system libraries.
    // Zig modules are the preferred way of making Zig code available to consumers.
    // addModule defines a module that we intend to make available for importing
    // to our consumers. We must give it a name because a Zig package can expose
    // multiple modules and consumers will need to be able to specify which
    // module they want to access.
    // Create build options that can be accessed from source code
    const build_options = b.addOptions();
    build_options.addOption(bool, "enable_treesitter", enable_treesitter);

    const mod = b.addModule("aesop", .{
        // The root source file is the "entry point" of this module. Users of
        // this module will only be able to access public declarations contained
        // in this file, which means that if you have declarations that you
        // intend to expose to consumers that were defined in other files part
        // of this module, you will have to make sure to re-export them from
        // the root file.
        .root_source_file = b.path("src/root.zig"),
        // Later on we'll use this module as the root module of a test executable
        // which requires us to specify a target.
        .target = target,
    });
    // Add build options to module so source code can access them
    mod.addImport("build_options", build_options.createModule());

    // Here we define an executable. An executable needs to have a root module
    // which needs to expose a `main` function. While we could add a main function
    // to the module defined above, it's sometimes preferable to split business
    // business logic and the CLI into two separate modules.
    //
    // If your goal is to create a Zig library for others to use, consider if
    // it might benefit from also exposing a CLI tool. A parser library for a
    // data serialization format could also bundle a CLI syntax checker, for example.
    //
    // If instead your goal is to create an executable, consider if users might
    // be interested in also being able to embed the core functionality of your
    // program in their own executable in order to avoid the overhead involved in
    // subprocessing your CLI tool.
    //
    // If neither case applies to you, feel free to delete the declaration you
    // don't need and to put everything under a single module.
    // Add zio dependency
    const zio_dep = b.dependency("zio", .{
        .target = target,
        .optimize = optimize,
    });
    const zio_module = zio_dep.module("zio");

    // Add zigjr dependency for LSP JSON-RPC
    const zigjr_dep = b.dependency("zigjr", .{
        .target = target,
        .optimize = optimize,
    });
    const zigjr_module = zigjr_dep.module("zigjr");

    const exe = b.addExecutable(.{
        .name = "aesop",
        .root_module = b.createModule(.{
            // b.createModule defines a new module just like b.addModule but,
            // unlike b.addModule, it does not expose the module to consumers of
            // this package, which is why in this case we don't have to give it a name.
            .root_source_file = b.path("src/main.zig"),
            // Target and optimization levels must be explicitly wired in when
            // defining an executable or library (in the root module), and you
            // can also hardcode a specific target for an executable or library
            // definition if desireable (e.g. firmware for embedded devices).
            .target = target,
            .optimize = optimize,
            // List of modules available for import in source files part of the
            // root module.
            .imports = &.{
                // Here "aesop" is the name you will use in your source code to
                // import this module (e.g. `@import("aesop")`). The name is
                // repeated because you are allowed to rename your imports, which
                // can be extremely useful in case of collisions (which can happen
                // importing modules from different packages).
                .{ .name = "aesop", .module = mod },
                .{ .name = "zio", .module = zio_module },
                .{ .name = "zigjr", .module = zigjr_module },
                .{ .name = "build_options", .module = build_options.createModule() },
            },
        }),
    });

    // Optionally link tree-sitter library for syntax highlighting
    // Note: tree-sitter must be installed on the system
    // See docs/BUILDING_WITH_TREE_SITTER.md for installation instructions
    if (enable_treesitter) {
        exe.linkSystemLibrary("tree-sitter");
        exe.linkLibC();

        // Note: Library paths need to be configured manually via DYLD_LIBRARY_PATH,
        // LD_LIBRARY_PATH, or system installation. We don't set them here to avoid
        // platform-specific code (Windows doesn't support std.posix.getenv).

        // Link language grammar libraries
        // Note: Each grammar must be built and installed separately
        // See docs/BUILDING_WITH_TREE_SITTER.md for per-language installation
        // If a grammar is not installed, linking will fail - install grammars first
        exe.linkSystemLibrary("tree-sitter-zig");
        exe.linkSystemLibrary("tree-sitter-rust");
        exe.linkSystemLibrary("tree-sitter-go");
        exe.linkSystemLibrary("tree-sitter-python");
        exe.linkSystemLibrary("tree-sitter-c");
    }

    // This declares intent for the executable to be installed into the
    // install prefix when running `zig build` (i.e. when executing the default
    // step). By default the install prefix is `zig-out/` but can be overridden
    // by passing `--prefix` or `-p`.
    b.installArtifact(exe);

    // This creates a top level step. Top level steps have a name and can be
    // invoked by name when running `zig build` (e.g. `zig build run`).
    // This will evaluate the `run` step rather than the default step.
    // For a top level step to actually do something, it must depend on other
    // steps (e.g. a Run step, as we will see in a moment).
    const run_step = b.step("run", "Run the app");

    // This creates a RunArtifact step in the build graph. A RunArtifact step
    // invokes an executable compiled by Zig. Steps will only be executed by the
    // runner if invoked directly by the user (in the case of top level steps)
    // or if another step depends on it, so it's up to you to define when and
    // how this Run step will be executed. In our case we want to run it when
    // the user runs `zig build run`, so we create a dependency link.
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // By making the run step depend on the default step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Creates an executable that will run `test` blocks from the provided module.
    // Here `mod` needs to define a target, which is why earlier we made sure to
    // set the releative field.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    // Optionally link tree-sitter for module tests
    if (enable_treesitter) {
        mod_tests.linkSystemLibrary("tree-sitter");
        mod_tests.linkLibC();
        mod_tests.linkSystemLibrary("tree-sitter-zig");
        mod_tests.linkSystemLibrary("tree-sitter-rust");
        mod_tests.linkSystemLibrary("tree-sitter-go");
        mod_tests.linkSystemLibrary("tree-sitter-python");
        mod_tests.linkSystemLibrary("tree-sitter-c");
    }

    // A run step that will run the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module. Note that test executables only test one module at a time,
    // hence why we have to create two separate ones.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    // Optionally link tree-sitter for exe tests
    if (enable_treesitter) {
        exe_tests.linkSystemLibrary("tree-sitter");
        exe_tests.linkLibC();
        exe_tests.linkSystemLibrary("tree-sitter-zig");
        exe_tests.linkSystemLibrary("tree-sitter-rust");
        exe_tests.linkSystemLibrary("tree-sitter-go");
        exe_tests.linkSystemLibrary("tree-sitter-python");
        exe_tests.linkSystemLibrary("tree-sitter-c");
    }

    // A run step that will run the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // Integration tests (tests/integration/)
    // These test full subsystem interactions using mock components
    const integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/rendering_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aesop", .module = mod },
                .{ .name = "zio", .module = zio_module },
                .{ .name = "zigjr", .module = zigjr_module },
            },
        }),
    });
    // Optionally link tree-sitter for integration tests
    if (enable_treesitter) {
        integration_tests.linkSystemLibrary("tree-sitter");
        integration_tests.linkLibC();
        integration_tests.linkSystemLibrary("tree-sitter-zig");
        integration_tests.linkSystemLibrary("tree-sitter-rust");
        integration_tests.linkSystemLibrary("tree-sitter-go");
        integration_tests.linkSystemLibrary("tree-sitter-python");
        integration_tests.linkSystemLibrary("tree-sitter-c");
    }

    const run_integration_tests = b.addRunArtifact(integration_tests);

    // Input integration tests
    const input_integration_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/input_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "aesop", .module = mod },
                .{ .name = "zio", .module = zio_module },
                .{ .name = "zigjr", .module = zigjr_module },
            },
        }),
    });
    // Optionally link tree-sitter for input integration tests
    if (enable_treesitter) {
        input_integration_tests.linkSystemLibrary("tree-sitter");
        input_integration_tests.linkLibC();
        input_integration_tests.linkSystemLibrary("tree-sitter-zig");
        input_integration_tests.linkSystemLibrary("tree-sitter-rust");
        input_integration_tests.linkSystemLibrary("tree-sitter-go");
        input_integration_tests.linkSystemLibrary("tree-sitter-python");
        input_integration_tests.linkSystemLibrary("tree-sitter-c");
    }

    const run_input_integration_tests = b.addRunArtifact(input_integration_tests);

    // A top level step for running all tests. dependOn can be called multiple
    // times and since the two run steps do not depend on one another, this will
    // make the two of them run in parallel.
    const test_step = b.step("test", "Run all tests (unit + integration)");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
    test_step.dependOn(&run_integration_tests.step);
    test_step.dependOn(&run_input_integration_tests.step);

    // Separate integration test step for selective testing
    const integration_test_step = b.step("test-integration", "Run integration tests only");
    integration_test_step.dependOn(&run_integration_tests.step);
    integration_test_step.dependOn(&run_input_integration_tests.step);

    // Unit tests only
    const unit_test_step = b.step("test-unit", "Run unit tests only");
    unit_test_step.dependOn(&run_mod_tests.step);
    unit_test_step.dependOn(&run_exe_tests.step);

    // Just like flags, top level steps are also listed in the `--help` menu.
    //
    // The Zig build system is entirely implemented in userland, which means
    // that it cannot hook into private compiler APIs. All compilation work
    // orchestrated by the build system will result in other Zig compiler
    // subcommands being invoked with the right flags defined. You can observe
    // these invocations when one fails (or you pass a flag to increase
    // verbosity) to validate assumptions and diagnose problems.
    //
    // Lastly, the Zig build system is relatively simple and self-contained,
    // and reading its source code will allow you to master it.
}
