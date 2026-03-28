# Fast MCP Server Tutorial

`fast-mcp` exposes Fast's Ruby AST search and rewrite primitives as MCP tools over stdio. It is best when an LLM host can register an MCP server and call tools directly instead of parsing CLI text output.

## What the server exposes

The current server exposes five tools:

1. `search_ruby_ast`
2. `ruby_method_source`
3. `ruby_class_source`
4. `rewrite_ruby`
5. `rewrite_ruby_file`

These are MCP `tools`, not MCP `resources`. If your host lists resources/templates and shows nothing, that does not mean the server is broken. It means the host has not connected to the server's tool interface.

## When MCP is better than CLI

Use MCP when:

- Your host supports MCP server registration and tool calling.
- You want structured JSON results without asking the model to parse CLI text.
- You want the host to decide when to call `ruby_method_source` or `search_ruby_ast` as a first-class tool.

Use the CLI when:

- Your host cannot register MCP servers.
- You only need ad hoc terminal searches.
- You want the simplest possible integration surface.

In practice, CLI is the easiest integration to get working. MCP is the better long-term interface for LLM agents because it preserves typed arguments and structured responses.

## Testing it locally with JSON-RPC

The server speaks JSON-RPC 2.0 over stdio through `bin/fast-mcp`.

### 1. List the tools

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' \
  | ruby -Ilib bin/fast-mcp
```

### 2. Extract a specific method

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"ruby_method_source","arguments":{"method_name":"search_all","paths":["lib"]}}}' \
  | ruby -Ilib bin/fast-mcp
```

This returns a JSON payload whose `result.content[0].text` is itself a JSON array of matches. Each match includes `file`, `line_start`, `line_end`, and the trimmed `code` snippet.

### 3. Extract a method from a known class

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"ruby_method_source","arguments":{"method_name":"run","class_name":"McpServer","paths":["lib"]}}}' \
  | ruby -Ilib bin/fast-mcp
```

This is often more token-efficient than returning the full class body.

### 4. Search with a raw AST pattern

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"search_ruby_ast","arguments":{"pattern":"(send nil :require (str _))","paths":["lib/fast/mcp_server.rb"]}}}' \
  | ruby -Ilib bin/fast-mcp
```

Set `"show_ast": true` only when you need the s-expression too.

### 5. Preview a rewrite without touching disk

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"rewrite_ruby","arguments":{"source":"def foo; puts 1; end","pattern":"(send nil :puts (int 1))","replacement":"logger.info('\''hello'\'')"}}}' \
  | ruby -Ilib bin/fast-mcp
```

Fast validates the rewritten Ruby before returning it. That matters for LLM workflows because a bad replacement fails early instead of feeding invalid code back into the next tool call.

### 6. Rewrite a file in place

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"rewrite_ruby_file","arguments":{"file":"lib/fast/mcp_server.rb","pattern":"(send nil :require (str \"json\"))","replacement":"require '\''json'\''"}}}' \
  | ruby -Ilib bin/fast-mcp
```

Prefer `rewrite_ruby` first to preview the change.

## Error behavior

- Missing paths return MCP error `-32603` with the underlying file error.
- Invalid AST patterns currently return an empty result array `[]`.
- Invalid rewrite output returns MCP error `-32603` with parser diagnostics, and `rewrite_ruby_file` does not modify the file.
- Unknown tool names return MCP error `-32603`.

## Current limitations

- `ruby_method_source` with `class_name` filters by file membership, not lexical scope. If a file defines the class anywhere, matching methods in that file can pass the filter.
- `ruby_class_source` returns the full class body, which can still be large for token-sensitive workflows.
- Hosts must register the server explicitly. A raw MCP resource list will stay empty because this server does not publish resources.

## Best practices

- Start with `ruby_method_source` when you know the method name.
- Use `search_ruby_ast` for call sites and structural queries.
- Prefer method-level extraction over class-level extraction to save tokens.
- Fall back to the CLI for hosts that cannot call MCP tools yet.
