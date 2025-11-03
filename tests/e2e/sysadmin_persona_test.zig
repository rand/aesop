//! E2E tests for sysadmin persona workflow
//! Simulates a sysadmin editing configuration files

const std = @import("std");
const testing = std.testing;
const Helpers = @import("../helpers.zig");
const Buffer = @import("../../src/buffer/manager.zig").Buffer;
const Window = @import("../../src/editor/window.zig");

test "sysadmin persona: edit nginx config" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, "/etc/nginx/nginx.conf");
    defer buffer.deinit();

    const config =
        \\server {
        \\    listen 80;
        \\    server_name example.com;
        \\
        \\    location / {
        \\        proxy_pass http://localhost:3000;
        \\    }
        \\}
    ;

    try buffer.rope.insert(0, config);

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "listen 80") != null);
    try testing.expect(std.mem.indexOf(u8, content, "proxy_pass") != null);
}

test "sysadmin persona: edit and reload systemd unit" {
    const allocator = testing.allocator;

    var buffer = try Buffer.init(allocator, "/etc/systemd/system/myapp.service");
    defer buffer.deinit();

    const unit =
        \\[Unit]
        \\Description=My Application
        \\After=network.target
        \\
        \\[Service]
        \\Type=simple
        \\User=myapp
        \\ExecStart=/usr/bin/myapp
        \\Restart=always
        \\
        \\[Install]
        \\WantedBy=multi-user.target
    ;

    try buffer.rope.insert(0, unit);

    try Helpers.Assertions.expectLineCount(&buffer, 11);

    // Verify service configuration
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "[Unit]") != null);
    try testing.expect(std.mem.indexOf(u8, content, "Restart=always") != null);
}

test "sysadmin persona: update environment variables" {
    const allocator = testing.allocator;

    const env =
        \\export PATH=/usr/local/bin:$PATH
        \\export DATABASE_URL=postgres://localhost/mydb
        \\export API_KEY=secret123
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(env);
    defer buffer.deinit();

    // Change API_KEY value
    const key_pos = std.mem.indexOf(u8, env, "secret123").?;
    try buffer.rope.delete(key_pos, 9); // Delete "secret123"
    try buffer.rope.insert(key_pos, "newsecret456");

    const updated = try buffer.rope.toString(allocator);
    defer allocator.free(updated);

    try testing.expect(std.mem.indexOf(u8, updated, "newsecret456") != null);
    try testing.expect(std.mem.indexOf(u8, updated, "secret123") == null);
}

test "sysadmin persona: split window for log monitoring" {
    const allocator = testing.allocator;

    var manager = try Window.WindowManager.init(allocator);
    defer manager.deinit();

    const root_id = manager.root.getId();

    // Split horizontally to show config and logs side by side
    const result = try manager.splitWindow(root_id, .horizontal, 0.5);

    // Verify two windows exist
    try testing.expect(manager.root.* == .split);
    try testing.expect(result.new_id != root_id);
}

test "sysadmin persona: search logs for errors" {
    const allocator = testing.allocator;

    const log_data =
        \\2025-11-03 10:00:00 INFO Server started
        \\2025-11-03 10:01:23 ERROR Connection refused to database
        \\2025-11-03 10:02:45 INFO Request processed
        \\2025-11-03 10:03:12 ERROR Out of memory
        \\2025-11-03 10:04:00 INFO Server healthy
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(log_data);
    defer buffer.deinit();

    // Search for ERROR lines
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    var error_count: usize = 0;
    var pos: usize = 0;
    while (std.mem.indexOfPos(u8, content, pos, "ERROR")) |found| {
        error_count += 1;
        pos = found + 5;
    }

    try testing.expectEqual(@as(usize, 2), error_count);
}

test "sysadmin persona: edit crontab" {
    const allocator = testing.allocator;

    const crontab =
        \\# Daily backup at 2 AM
        \\0 2 * * * /usr/local/bin/backup.sh
        \\
        \\# Weekly cleanup on Sundays at 3 AM
        \\0 3 * * 0 /usr/local/bin/cleanup.sh
        \\
        \\# Hourly health check
        \\0 * * * * /usr/local/bin/healthcheck.sh
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(crontab);
    defer buffer.deinit();

    try Helpers.Assertions.expectLineCount(&buffer, 7);

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "backup.sh") != null);
    try testing.expect(std.mem.indexOf(u8, content, "cleanup.sh") != null);
}

test "sysadmin persona: configure firewall rules" {
    const allocator = testing.allocator;

    const rules =
        \\# Allow SSH
        \\-A INPUT -p tcp --dport 22 -j ACCEPT
        \\
        \\# Allow HTTP and HTTPS
        \\-A INPUT -p tcp --dport 80 -j ACCEPT
        \\-A INPUT -p tcp --dport 443 -j ACCEPT
        \\
        \\# Drop all other incoming
        \\-A INPUT -j DROP
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(rules);
    defer buffer.deinit();

    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "dport 22") != null);
    try testing.expect(std.mem.indexOf(u8, content, "dport 443") != null);
}

test "sysadmin persona: edit hosts file" {
    const allocator = testing.allocator;

    const hosts =
        \\127.0.0.1       localhost
        \\::1             localhost
        \\192.168.1.10    db-server
        \\192.168.1.11    app-server
        \\192.168.1.12    cache-server
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(hosts);
    defer buffer.deinit();

    // Add new host entry
    const new_entry = "\n192.168.1.13    backup-server";
    try buffer.rope.insert(buffer.rope.len(), new_entry);

    const updated = try buffer.rope.toString(allocator);
    defer allocator.free(updated);

    try testing.expect(std.mem.indexOf(u8, updated, "backup-server") != null);
}

test "sysadmin persona: validate JSON config" {
    const allocator = testing.allocator;

    const json_config =
        \\{
        \\  "server": {
        \\    "port": 8080,
        \\    "host": "0.0.0.0"
        \\  },
        \\  "database": {
        \\    "host": "localhost",
        \\    "port": 5432
        \\  }
        \\}
    ;

    var buffer = try Helpers.BufferBuilder.init(allocator).withContent(json_config);
    defer buffer.deinit();

    // Verify JSON structure present
    const content = try buffer.rope.toString(allocator);
    defer allocator.free(content);

    try testing.expect(std.mem.indexOf(u8, content, "\"server\"") != null);
    try testing.expect(std.mem.indexOf(u8, content, "\"database\"") != null);
}

test "sysadmin persona: multi-file configuration" {
    const allocator = testing.allocator;

    // Simulate editing multiple config files
    var nginx_conf = try Buffer.init(allocator, "nginx.conf");
    defer nginx_conf.deinit();

    var app_conf = try Buffer.init(allocator, "app.conf");
    defer app_conf.deinit();

    var db_conf = try Buffer.init(allocator, "database.conf");
    defer db_conf.deinit();

    try nginx_conf.rope.insert(0, "worker_processes 4;\n");
    try app_conf.rope.insert(0, "workers = 8\n");
    try db_conf.rope.insert(0, "max_connections = 100\n");

    // Verify all buffers have content
    try testing.expect(nginx_conf.rope.len() > 0);
    try testing.expect(app_conf.rope.len() > 0);
    try testing.expect(db_conf.rope.len() > 0);
}
