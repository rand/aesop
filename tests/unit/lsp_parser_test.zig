//! Unit tests for LSP response parsing

const std = @import("std");
const testing = std.testing;
const ResponseParser = @import("../../src/lsp/response_parser.zig");

test "lsp parser: parse completion response" {
    const allocator = testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":1,"result":[
        \\  {"label":"foo","kind":3},
        \\  {"label":"bar","kind":3}
        \\]}
    ;

    const items = try ResponseParser.parseCompletionResponse(allocator, json);
    defer {
        for (items) |*item| {
            item.deinit(allocator);
        }
        allocator.free(items);
    }

    try testing.expectEqual(@as(usize, 2), items.len);
    try testing.expectEqualStrings("foo", items[0].label);
    try testing.expectEqualStrings("bar", items[1].label);
}

test "lsp parser: parse empty completion" {
    const allocator = testing.allocator;

    const json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":[]}";

    const items = try ResponseParser.parseCompletionResponse(allocator, json);
    defer allocator.free(items);

    try testing.expectEqual(@as(usize, 0), items.len);
}

test "lsp parser: parse hover response" {
    const allocator = testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":1,"result":{
        \\  "contents":{"kind":"markdown","value":"# Function\nSome documentation"}
        \\}}
    ;

    const hover = try ResponseParser.parseHoverResponse(allocator, json);
    defer if (hover) |h| allocator.free(h);

    try testing.expect(hover != null);
    try testing.expect(std.mem.indexOf(u8, hover.?, "Function") != null);
}

test "lsp parser: parse null hover response" {
    const allocator = testing.allocator;

    const json = "{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":null}";

    const hover = try ResponseParser.parseHoverResponse(allocator, json);
    try testing.expect(hover == null);
}

test "lsp parser: parse diagnostic notification" {
    const allocator = testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","method":"textDocument/publishDiagnostics","params":{
        \\  "uri":"file:///test.zig",
        \\  "diagnostics":[{
        \\    "range":{"start":{"line":5,"character":0},"end":{"line":5,"character":10}},
        \\    "severity":1,
        \\    "message":"Error message"
        \\  }]
        \\}}
    ;

    const diagnostics = try ResponseParser.parseDiagnosticNotification(allocator, json);
    defer {
        for (diagnostics.diagnostics) |*diag| {
            diag.deinit(allocator);
        }
        allocator.free(diagnostics.diagnostics);
        allocator.free(diagnostics.uri);
    }

    try testing.expectEqualStrings("file:///test.zig", diagnostics.uri);
    try testing.expectEqual(@as(usize, 1), diagnostics.diagnostics.len);
    try testing.expectEqual(@as(u32, 5), diagnostics.diagnostics[0].range.start.line);
}

test "lsp parser: parse definition response" {
    const allocator = testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":1,"result":{
        \\  "uri":"file:///test.zig",
        \\  "range":{"start":{"line":10,"character":5},"end":{"line":10,"character":15}}
        \\}}
    ;

    const location = try ResponseParser.parseDefinitionResponse(allocator, json);
    defer if (location) |loc| {
        allocator.free(loc.uri);
    };

    try testing.expect(location != null);
    try testing.expectEqualStrings("file:///test.zig", location.?.uri);
    try testing.expectEqual(@as(u32, 10), location.?.range.start.line);
}

test "lsp parser: parse signature help" {
    const allocator = testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":1,"result":{
        \\  "signatures":[{
        \\    "label":"function(x: i32, y: i32) i32",
        \\    "parameters":[
        \\      {"label":"x: i32"},
        \\      {"label":"y: i32"}
        \\    ]
        \\  }],
        \\  "activeSignature":0,
        \\  "activeParameter":0
        \\}}
    ;

    const help = try ResponseParser.parseSignatureHelpResponse(allocator, json);
    defer if (help) |h| {
        for (h.signatures) |*sig| {
            sig.deinit(allocator);
        }
        allocator.free(h.signatures);
    };

    try testing.expect(help != null);
    try testing.expectEqual(@as(usize, 1), help.?.signatures.len);
    try testing.expectEqual(@as(usize, 2), help.?.signatures[0].parameters.len);
}

test "lsp parser: parse code actions" {
    const allocator = testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":1,"result":[
        \\  {"title":"Fix issue","kind":"quickfix"},
        \\  {"title":"Refactor","kind":"refactor"}
        \\]}
    ;

    const actions = try ResponseParser.parseCodeActionsResponse(allocator, json);
    defer {
        for (actions) |*action| {
            action.deinit(allocator);
        }
        allocator.free(actions);
    }

    try testing.expectEqual(@as(usize, 2), actions.len);
    try testing.expectEqualStrings("Fix issue", actions[0].title);
    try testing.expectEqualStrings("Refactor", actions[1].title);
}

test "lsp parser: parse workspace edit" {
    const allocator = testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":1,"result":{
        \\  "changes":{
        \\    "file:///test.zig":[{
        \\      "range":{"start":{"line":5,"character":0},"end":{"line":5,"character":10}},
        \\      "newText":"replacement"
        \\    }]
        \\  }
        \\}}
    ;

    const edit = try ResponseParser.parseRenameResponse(allocator, json);
    defer if (edit) |e| {
        var iter = e.changes.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            for (entry.value_ptr.*) |*text_edit| {
                allocator.free(text_edit.new_text);
            }
            allocator.free(entry.value_ptr.*);
        }
        e.changes.deinit();
    };

    try testing.expect(edit != null);
    try testing.expectEqual(@as(usize, 1), edit.?.changes.count());
}

test "lsp parser: parse document symbols" {
    const allocator = testing.allocator;

    const json =
        \\{"jsonrpc":"2.0","id":1,"result":[
        \\  {
        \\    "name":"MyFunction",
        \\    "kind":12,
        \\    "range":{"start":{"line":10,"character":0},"end":{"line":20,"character":0}},
        \\    "selectionRange":{"start":{"line":10,"character":4},"end":{"line":10,"character":14}}
        \\  }
        \\]}
    ;

    const symbols = try ResponseParser.parseDocumentSymbolResponse(allocator, json);
    defer {
        for (symbols) |*symbol| {
            symbol.deinit(allocator);
        }
        allocator.free(symbols);
    }

    try testing.expectEqual(@as(usize, 1), symbols.len);
    try testing.expectEqualStrings("MyFunction", symbols[0].name);
    try testing.expectEqual(@as(u16, 12), @intFromEnum(symbols[0].kind));
}
