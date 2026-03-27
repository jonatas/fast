# Fast MCP Server Tutorial

Welcome! `fast` now ships with an extremely powerful `fast-mcp` execution server designed to act as an AST search backend for LLMs via the Model Context Protocol (MCP). Let's explore everything it can do!

## Tools Available
The server exposes four highly optimized tools to navigate Ruby code structure reliably without spamming you with full files.
1. `search_ruby_ast`
2. `ruby_method_source`
3. `ruby_class_source`
4. `rewrite_ruby`

## Testing it Locally with JSON-RPC

Since MCP expects JSON-RPC 2.0 requests over stdio, you can send manual queries to `bin/fast-mcp`.

### 1. Extracting a specific method
Need to fetch exactly how `def search_all` is implemented? Send this to STDIN:
```json
{"jsonrpc":"2.0", "id": 1, "method": "tools/call", "params": {"name": "ruby_method_source", "arguments": {"method_name": "search_all", "paths": ["lib"]}}}
```
**Output Highlights**: You will get back an array in the `result.content` showing EXACTLY the method block start to finish `def search_all... end`, perfectly trimmed with line boundaries `[195..206]`.

### 2. Extracting an entire class
Need the structural definition of `class Cli`?
```json
{"jsonrpc":"2.0", "id": 2, "method": "tools/call", "params": {"name": "ruby_class_source", "arguments": {"class_name": "Cli", "paths": ["lib"]}}}
```
This is fully syntax-aware so it handles `class Fast::Cli` or `class Cli < Object` effortlessly, unlike grep where you might catch random string tokens.

### 3. Using Raw AST Patterns (`search_ruby_ast`)
You can tap directly into the rubocop AST matching syntax for massive flexibility:
```json
{"jsonrpc":"2.0", "id": 3, "method": "tools/call", "params": {"name": "search_ruby_ast", "arguments": {"pattern": "(send nil :require (str _))", "paths": ["lib/fast.rb"]}}}
```
*Tip: If you want to dive into the raw S-expression for the file, set `"show_ast": true` inside `arguments`.*

### 4. Code Rewriting (`rewrite_ruby`)
Want to quickly draft a refactor using the tool before doing it with standard editing commands? You can ask `fast-mcp` to apply a fast rewrite AST replacement inline to check the output!
```json
{"jsonrpc":"2.0", "id": 4, "method": "tools/call", "params": {"name": "rewrite_ruby", "arguments": {"source": "def foo; puts 1; end", "pattern": "(send nil :puts (int 1))", "replacement": "logger.info('hello')"}}}
```
Returns a diff mapping object `{"rewritten": "def foo; logger.info('hello'); end"}`.

## Error Handling Edge Cases
- **Missing Paths**: If you supply a path that doesn't exist, the tool safely catches `rb_sysopen` and returns an MCP Error code -32603, avoiding a server crash.
- **Parse Errors / Mismatches**: If you supply an invalid ruby block like `(def unclosed`, `fast` gracefully isolates the search expression mismatch to return an empty `[]` search result rather than destroying the process context. 

## Best Practices
- Fast AST queries are exceptionally precise but can occasionally miss syntax edge-cases (e.g. `send` with blocks might require `block` matcher first). When in doubt, perform a generic text search first to grab the `show_ast: true` signature!
