//! LSP server process management
//! Handles spawning, I/O, and lifecycle of language server processes

const std = @import("std");

/// Context for stderr logging thread
const StderrContext = struct {
    file: std.fs.File,
    running: *const std.atomic.Value(bool),
};

/// Background thread that logs LSP stderr to file
fn stderrLogger(context: StderrContext) void {
    // Get log file path: ~/.aesop/lsp-stderr.log
    const home = std.posix.getenv("HOME") orelse {
        return; // Can't determine home directory
    };

    // Create ~/.aesop directory if needed
    var home_dir = std.fs.openDirAbsolute(home, .{}) catch return;
    defer home_dir.close();

    home_dir.makeDir(".aesop") catch |err| {
        if (err != error.PathAlreadyExists) return;
    };

    var aesop_dir = home_dir.openDir(".aesop", .{}) catch return;
    defer aesop_dir.close();

    // Open log file for appending
    const log_file = aesop_dir.createFile("lsp-stderr.log", .{
        .truncate = false,
        .read = false,
    }) catch return;
    defer log_file.close();

    // Seek to end for appending
    log_file.seekFromEnd(0) catch {};

    // Add timestamp header
    const timestamp = std.time.timestamp();
    var header_buf: [256]u8 = undefined;
    const header = std.fmt.bufPrint(&header_buf, "\n=== LSP session started at {d} ===\n", .{timestamp}) catch return;
    log_file.writeAll(header) catch {};

    // Read stderr and write to log
    var buffer: [4096]u8 = undefined;
    while (context.running.load(.seq_cst)) {
        const n = context.file.read(&buffer) catch break;
        if (n == 0) {
            std.time.sleep(10 * std.time.ns_per_ms); // Sleep 10ms if no data
            continue;
        }

        log_file.writeAll(buffer[0..n]) catch {};
    }

    // Write session end marker
    const footer = "\n=== LSP session ended ===\n";
    log_file.writeAll(footer) catch {};
}

/// Language server process manager
pub const Process = struct {
    allocator: std.mem.Allocator,
    child: ?std.process.Child,
    stdin: ?std.fs.File,
    stdout: ?std.fs.File,
    stderr_thread: ?std.Thread = null,
    stderr_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    command: []const u8,
    args: []const []const u8,
    running: bool,
    restart_count: usize,
    max_restarts: usize = 3,

    /// Initialize process manager (does not spawn)
    pub fn init(allocator: std.mem.Allocator, command: []const u8, args: []const []const u8) Process {
        return .{
            .allocator = allocator,
            .child = null,
            .stdin = null,
            .stdout = null,
            .command = command,
            .args = args,
            .running = false,
            .restart_count = 0,
        };
    }

    /// Clean up process
    pub fn deinit(self: *Process) void {
        self.stop() catch {};
    }

    /// Spawn the language server process
    pub fn spawn(self: *Process) !void {
        if (self.running) return error.AlreadyRunning;

        // Build argv
        var argv = std.ArrayList([]const u8).init(self.allocator);
        defer argv.deinit();
        try argv.append(self.command);
        for (self.args) |arg| {
            try argv.append(arg);
        }

        // Spawn child process with stdio pipes
        var child = std.process.Child.init(argv.items, self.allocator);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe; // Capture stderr for logging

        try child.spawn();

        self.child = child;
        self.stdin = child.stdin;
        self.stdout = child.stdout;
        self.running = true;

        // Start background thread to log stderr
        if (child.stderr) |stderr| {
            self.stderr_running.store(true, .seq_cst);
            const context = StderrContext{
                .file = stderr,
                .running = &self.stderr_running,
            };
            self.stderr_thread = try std.Thread.spawn(.{}, stderrLogger, .{context});
        }
    }

    /// Stop the language server process
    pub fn stop(self: *Process) !void {
        if (!self.running) return;

        // Signal stderr thread to stop
        if (self.stderr_thread) |thread| {
            self.stderr_running.store(false, .seq_cst);
            thread.join();
            self.stderr_thread = null;
        }

        if (self.child) |*child| {
            // Send termination signal
            _ = child.kill() catch {};
            _ = try child.wait();
        }

        self.child = null;
        self.stdin = null;
        self.stdout = null;
        self.running = false;
    }

    /// Restart the process (with backoff)
    pub fn restart(self: *Process) !void {
        if (self.restart_count >= self.max_restarts) {
            return error.TooManyRestarts;
        }

        try self.stop();

        // Exponential backoff: 100ms, 200ms, 400ms
        const delay_ms = (@as(u64, 100) << @intCast(self.restart_count));
        std.time.sleep(delay_ms * std.time.ns_per_ms);

        try self.spawn();
        self.restart_count += 1;
    }

    /// Write JSON-RPC message with content-length framing
    pub fn writeMessage(self: *Process, json: []const u8) !void {
        const stdin = self.stdin orelse return error.ProcessNotRunning;

        // Calculate content length
        const content_length = json.len;

        // Write header: "Content-Length: 123\r\n\r\n"
        var header_buf: [128]u8 = undefined;
        const header = try std.fmt.bufPrint(&header_buf, "Content-Length: {d}\r\n\r\n", .{content_length});

        // Write header + body
        try stdin.writeAll(header);
        try stdin.writeAll(json);
    }

    /// Read JSON-RPC message (blocking with content-length parsing)
    pub fn readMessage(self: *Process, buffer: []u8) ![]const u8 {
        const stdout = self.stdout orelse return error.ProcessNotRunning;

        // Read header line by line until we find Content-Length
        var content_length: usize = 0;
        var header_buf: [512]u8 = undefined;
        var header_pos: usize = 0;

        // Read headers
        while (header_pos < header_buf.len) {
            const byte = try stdout.reader().readByte();
            header_buf[header_pos] = byte;
            header_pos += 1;

            // Check for end of headers (\r\n\r\n)
            if (header_pos >= 4 and
                std.mem.eql(u8, header_buf[header_pos - 4 .. header_pos], "\r\n\r\n"))
            {
                break;
            }

            // Parse Content-Length when we see \r\n
            if (header_pos >= 2 and std.mem.eql(u8, header_buf[header_pos - 2 .. header_pos], "\r\n")) {
                const line = header_buf[0 .. header_pos - 2];
                if (std.mem.startsWith(u8, line, "Content-Length: ")) {
                    const length_str = line["Content-Length: ".len..];
                    content_length = try std.fmt.parseInt(usize, length_str, 10);
                }
                // Reset for next header line (keep accumulating in header_buf)
            }
        }

        if (content_length == 0) {
            return error.MissingContentLength;
        }

        if (content_length > buffer.len) {
            return error.MessageTooLarge;
        }

        // Read body
        var total_read: usize = 0;
        while (total_read < content_length) {
            const n = try stdout.read(buffer[total_read..content_length]);
            if (n == 0) return error.UnexpectedEOF;
            total_read += n;
        }

        return buffer[0..content_length];
    }

    /// Check if process is running
    pub fn isRunning(self: *const Process) bool {
        return self.running;
    }
};

// === Tests ===

test "process: init and deinit" {
    const allocator = std.testing.allocator;
    var process = Process.init(allocator, "cat", &[_][]const u8{});
    defer process.deinit();

    try std.testing.expect(!process.isRunning());
}

test "process: content-length framing" {

    // Simulate writing a message
    const json = "{\"jsonrpc\":\"2.0\",\"id\":1}";
    const expected_header = "Content-Length: 24\r\n\r\n";

    var buf: [256]u8 = undefined;
    const header = try std.fmt.bufPrint(&buf, "Content-Length: {d}\r\n\r\n", .{json.len});

    try std.testing.expectEqualStrings(expected_header, header);
}

test "process: parse content-length from header" {
    const header = "Content-Length: 123\r\n\r\n";
    const prefix = "Content-Length: ";

    var length: usize = 0;
    if (std.mem.indexOf(u8, header, prefix)) |start| {
        const end = std.mem.indexOf(u8, header[start..], "\r\n") orelse return error.InvalidHeader;
        const length_str = header[start + prefix.len .. start + end];
        length = try std.fmt.parseInt(usize, length_str, 10);
    }

    try std.testing.expectEqual(@as(usize, 123), length);
}
