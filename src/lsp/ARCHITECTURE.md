# LSP Client Architecture

## Module Structure

```
src/lsp/
├── client.zig       - Client state machine + JSON-RPC layer
├── sync.zig         - Text document synchronization
├── process.zig      - Language server process management (NEW)
├── handlers.zig     - LSP request/response handlers (NEW)
└── ARCHITECTURE.md  - This file
```

## Data Flow

```
Editor Buffer Event
    ↓
Editor (editor.zig)
    ↓
LSP Client (client.zig)
    ↓ serialize via zigjr
JSON-RPC Message
    ↓
Process Manager (process.zig)
    ↓ write to stdin
Language Server Process
    ↓ read from stdout
Process Manager (process.zig)
    ↓ parse via zigjr
JSON-RPC Response
    ↓
Handler (handlers.zig)
    ↓
Editor Update
```

## Module Responsibilities

### client.zig
- **State machine**: uninitialized → initializing → initialized → shutdown → exited
- **Request tracking**: Map request IDs to callbacks
- **JSON-RPC serialization**: Use zigjr for request/response marshaling
- **Request lifecycle**: Send requests, await responses, handle errors
- **Notification dispatch**: Handle server-initiated notifications

### sync.zig (existing)
- **Document state tracking**: URI → version mapping
- **didOpen/didChange/didSave/didClose**: Create notification payloads
- **Version management**: Increment document versions on changes

### process.zig (new)
- **Process spawning**: Launch language server with stdio pipes
- **I/O management**: Read/write with content-length framing
- **Process lifecycle**: Start, restart on crash, clean shutdown
- **Stream parsing**: Extract messages from stdout stream
- **Error handling**: Server crashes, broken pipes, timeouts

### handlers.zig (new)
- **Request handlers**:
  - `initialize`: Capability negotiation
  - `textDocument/completion`: Code completion
  - `textDocument/hover`: Hover information
  - `textDocument/definition`: Go to definition
- **Response parsers**: Extract typed data from JSON responses
- **Notification handlers**: Process server-initiated messages (diagnostics, etc.)

## Integration Points

### Editor → LSP
- `editor.openFile()` → `client.didOpen()`
- `editor.save()` → `client.didSave()`
- `editor.closeBuffer()` → `client.didClose()`
- `editor.processKey()` (text change) → `client.didChange()`
- Command: `complete` → `client.completion()`
- Command: `goto_definition` → `client.definition()`

### LSP → Editor
- Completion results → Show completion popup
- Diagnostics → Update gutter with error/warning indicators
- Hover info → Display in message area

## Message Protocol

### Content-Length Framing
```
Content-Length: 123\r\n
\r\n
{"jsonrpc":"2.0","id":1,"method":"initialize",...}
```

### Request Structure (zigjr)
```zig
const request = try zigjr.composer.makeRequestJson(
    allocator,
    "textDocument/completion",
    CompletionParams{ .textDocument = .{ .uri = uri }, .position = pos },
    zigjr.RpcId{ .num = request_id }
);
```

### Response Parsing (zigjr)
```zig
const rpc_response = try zigjr.parseRpcResponse(allocator, json_string);
defer rpc_response.deinit();
// Extract result, handle errors
```

## Initialization Sequence

1. Editor starts, loads LSP config (language → server command mapping)
2. On first buffer open for language:
   - `Process.spawn("zls")` (or configured server)
   - `Client.initialize()` → Send initialize request
   - Wait for initialize response → Extract server capabilities
   - `Client.sendInitialized()` → Send initialized notification
   - State → `.initialized`
3. Ready to accept document sync and requests

## Error Handling Strategy

- **Process crashes**: Auto-restart with exponential backoff
- **Request timeouts**: 5s default, callback with error
- **JSON parse errors**: Log and continue
- **Invalid responses**: Return error to caller
- **Server errors**: Extract error message, show in editor

## Concurrency Model

- **Single-threaded**: No async/await complexity
- **Non-blocking I/O**: Use `std.fs.File` with polling
- **Request queue**: Process one request at a time (FIFO)
- **Notifications**: Send immediately (no response expected)

## Testing Strategy

1. **Unit tests**: Each module independently
   - client.zig: State transitions, request tracking
   - process.zig: Message framing, process lifecycle
   - handlers.zig: Response parsing

2. **Integration tests**:
   - Spawn mock server, verify handshake
   - Send didOpen, verify content-length framing
   - Request completion, parse results

3. **End-to-end tests**:
   - Launch ZLS with test Zig file
   - Verify completion works
   - Verify hover works
   - Verify diagnostics appear

## Phase Implementation Order

### Phase A: JSON-RPC Layer (client.zig) - **PARALLEL**
- Add zigjr imports
- Implement `sendRequest()` → serialize, track ID
- Implement `sendNotification()` → serialize, no tracking
- Implement `handleResponse()` → parse, find callback, invoke

### Phase B: Process Management (process.zig) - **PARALLEL**
- Implement `Process.spawn(cmd)` → stdio pipes
- Implement `writeMessage(json)` → content-length + body
- Implement `readMessage()` → parse content-length, read body
- Implement restart logic

### Phase C: Core Handlers (handlers.zig) - **SEQUENTIAL** (depends on A)
- Implement initialize handshake
- Implement document sync (didOpen, didChange, didSave, didClose)
- Implement completion request
- Implement hover request
- Implement definition request

### Phase D: Editor Integration - **SEQUENTIAL** (depends on C)
- Hook buffer lifecycle events
- Add completion command + UI
- Add goto_definition command
- Wire up diagnostics display

### Phase E: Testing & Documentation - **FINAL**
- Write unit tests
- Test with ZLS
- Document configuration
- Add language server examples

## Configuration Format

```zig
// Future: config.zig LSP section
pub const LspConfig = struct {
    enabled: bool = true,
    servers: std.StringHashMap(ServerConfig),

    pub const ServerConfig = struct {
        command: []const u8,
        args: []const []const u8,
        filetypes: []const []const u8,
    };
};

// Example:
// zig → { command: "zls", args: [], filetypes: [".zig"] }
// rust → { command: "rust-analyzer", args: [], filetypes: [".rs"] }
```

## Performance Considerations

- **Lazy initialization**: Only spawn server when first file opened
- **Request batching**: Coalesce rapid didChange events
- **Incremental sync**: Send only changed ranges (future)
- **Response caching**: Cache hover/completion results (future)

## Future Enhancements

- Multiple language servers running concurrently
- Workspace folder support
- Configuration change notifications
- Incremental document sync (send diffs, not full content)
- Diagnostics rendering in gutter
- Code actions (quick fixes)
- Signature help
- Document symbols
- Workspace symbols
