# Using Fast for LLMs and Agents

`fast` is useful to LLM agents in two different ways:

1. As a CLI command the agent can run in a terminal.
2. As an MCP server through `bin/fast-mcp`.

Both help reduce token waste compared with raw text grep. The right integration depends on what the host can support.

## Why use `fast` over `grep`

- **Precision**: You can search for syntactic constructs (e.g., classes, method definitions, specific method calls) rather than just substrings.
- **Context Preservation**: `fast` inherently understands the bounds of a method or block. It will print the entire body of the AST node matched, not just the single line containing the keyword.
- **Token Efficiency**: Get only the function or class you want, instead of 100 lines of regex false positives.
- **File and Line Locality**: Outcomes are directly prefixed with the file and line number by default (`# file/path.rb:123`), making it trivial to know exactly where the code is located for further editing or patching.

## CLI or MCP

Choose CLI when:

- The host can run shell commands but cannot register MCP servers.
- You want the smallest possible setup and best portability.
- The agent is already comfortable parsing terminal output.

Choose MCP when:

- The host supports MCP registration and tool calling.
- You want typed arguments and structured JSON results.
- You want the model to call targeted tools like `ruby_method_source` instead of constructing shell commands.

For Codex-style terminal agents, the CLI is immediately useful and often enough. For IDE agents and multi-tool hosts, MCP is usually the better interface because it removes output parsing and makes tool selection explicit.

## Essential CLI flags for agents

To maximize reliability and reduce context noise, use these flags when invoking `fast` from the command line:

- `--no-color`: **CRITICAL**. Always use this flag to strip ANSI escape codes formatting out of the output. TTY color codes consume unnecessary tokens and break markdown parsing.
- `--headless`: Omits the `# filename.rb:line` header if you only want the raw code snippet and don't care about the location.
- `--bodyless`: Omits the code block body and only shows the matched headers (useful for finding *where* something is without reading *what* it is).
- `--ast`: Prints the S-expression representation of the matching nodes. Outstanding when you need to understand the internal AST structure of a complex ruby construct to construct more advanced `fast` queries or RuboCop node patterns.

## Essential MCP tools

If your host supports MCP, register `bin/fast-mcp` and call these tools:

- `search_ruby_ast`
- `ruby_method_source`
- `ruby_class_source`
- `rewrite_ruby`
- `rewrite_ruby_file`

These return JSON text payloads with file paths, line bounds, and trimmed code snippets. They are usually more robust for agents than scraping pretty CLI output.

## Query examples

### Finding method definitions

Instead of `grep -rn "def process" .`:

```bash
fast "(def process)" app/ lib/ --no-color
```

With MCP, call `ruby_method_source` with `method_name: "process"` and `paths: ["app", "lib"]`.

## Advanced search

You can use `^` to search upstream (e.g. parent nodes) or use `{}` for unions:

```bash
# Find classes that contain a specific method
fast "^(def my_specific_method)" app/ --no-color

# Find both `def_node_matcher` and `def_node_search` usage
fast "(send nil {def_node_matcher def_node_search})" lib/ --no-color
```

## Best practices for LLM context

1. **Initial Recon**: When entering a new file or directory, if you know the name of the function, use `fast "(def <name>)" <path> --no-color`.
2. **Finding References**: To find where a method is called, use `fast "(send _ :<name>)" <path> --no-color`.
3. **AST Inspection**: If you need to manipulate a complex file, you can output the AST of a specific method to construct a patch: `fast "(def <name>)" <file> --ast --no-color`.
4. **Prefer method-sized context**: Method extraction is usually the best token-saving unit for both CLI and MCP.
5. **Use MCP when available**: Agents should prefer MCP over CLI once the host can register the server, because structured tool calls are easier to orchestrate than parsing terminal output.
