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
- **Safer Rewrites**: Fast validates rewritten Ruby before returning it or writing it to disk. Invalid replacements fail with an error instead of silently producing broken code.

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

## Use `.summary` for first-pass reconnaissance

`fast .summary file.rb` is a high-leverage shortcut for agents entering a large file. Instead of reading the full body first, it prints a compact structural outline:

- class and module nesting
- constants
- mixins
- relationships such as `has_many` and `belongs_to`
- attributes such as `attr_reader`
- scopes, hooks, and validations
- method signatures grouped by visibility
- macro-heavy sections that would otherwise waste tokens

This is especially useful before deciding whether to fetch full method bodies through `fast`, MCP tools, or ordinary file reads.

## Use `.scan` for multi-file triage

`fast .scan path/to/dir --no-color` extends the same idea across many files. It classifies files into broad groups and prints a bounded per-file outline without dumping full bodies.

The scanner is designed to help agents avoid rabbit holes during repo exploration:

- group files into models, controllers, services, jobs, mailers, libraries, and other
- show one short headline per structural entry
- surface only the most useful signals such as hooks, validations, relationships, mixins, and macros
- list a capped set of public and private method names
- avoid printing method bodies, large constants, or implementation details by default

This makes `.scan` a better first move than reading a whole directory tree when the task is still about classification and narrowing scope.

## Essential MCP tools

If your host supports MCP, register `bin/fast-mcp` and call these tools:

- `search_ruby_ast`
- `ruby_method_source`
- `ruby_class_source`
- `rewrite_ruby`
- `rewrite_ruby_file`

These return JSON text payloads with file paths, line bounds, and trimmed code snippets. They are usually more robust for agents than scraping pretty CLI output.

## Why rewrite safety matters for agents

Many rewriting workflows only guarantee that a string replacement happened. They do not guarantee that the resulting source still parses. That is risky for LLM agents because one bad rewrite can poison the next tool call, confuse the model, or write broken files into the working tree.

Fast's rewrite path validates the rewritten Ruby after applying the replacement:

- `rewrite_ruby` fails instead of returning invalid Ruby.
- `rewrite_ruby_file` fails instead of writing invalid Ruby to disk.
- MCP surfaces this as a normal tool error, which is easier for agents to recover from than a corrupted file.

## Query examples

### Finding method definitions

Instead of `grep -rn "def process" .`:

```bash
fast "(def process)" app/ lib/ --no-color
```

With MCP, call `ruby_method_source` with `method_name: "process"` and `paths: ["app", "lib"]`.

### Summarizing a large file before reading it

```bash
fast .summary app/models/order.rb --no-color
```

This is often the best first step when the file is large and you need to decide which methods or macros deserve deeper inspection.

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
2. **Repo Triage**: When entering an unfamiliar directory, start with `fast .scan <path> --no-color` to classify files before reading anything deeply.
3. **Finding References**: To find where a method is called, use `fast "(send _ :<name>)" <path> --no-color`.
4. **AST Inspection**: If you need to manipulate a complex file, you can output the AST of a specific method to construct a patch: `fast "(def <name>)" <file> --ast --no-color`.
5. **Prefer method-sized context**: Method extraction is usually the best token-saving unit for both CLI and MCP.
6. **Use MCP when available**: Agents should prefer MCP over CLI once the host can register the server, because structured tool calls are easier to orchestrate than parsing terminal output.
7. **Preview before writing**: Prefer `rewrite_ruby` before `rewrite_ruby_file` so the agent can inspect the result even though invalid rewrites are already rejected.
8. **Use `.summary` before deep reads**: For unfamiliar large files, a summary is often the cheapest way to understand the shape before pulling full source.
9. **Use `.scan` before `.summary` at repo scale**: Scan first, then summarize only the small set of files that look relevant.

## Larger scenarios

### 1. Onboarding to a large Rails model

Start with `fast .summary app/models/order.rb --no-color`.

This lets the agent see:

- associations
- validations
- callbacks
- scopes
- public vs private method shape

That is a better starting point than reading 500 lines top to bottom, especially when most of the file is macro noise.

### 2. Auditing callback-heavy classes before a refactor

For files with many `before_*`, `after_*`, and macro declarations, `.summary` quickly exposes lifecycle hooks and method boundaries. The agent can then fetch only the callback implementations it actually needs.

### 3. Planning a rewrite safely

Use `.summary` first to identify the small set of methods or macros involved, then switch to `ruby_method_source`, `search_ruby_ast`, or `rewrite_ruby`. This reduces token use and lowers the chance of targeting the wrong scope.

### 4. Reviewing framework-heavy files

Controllers, jobs, mailers, and serializers often contain more declarations than logic. `.summary` helps the agent separate framework declarations from the few methods that contain actual behavior.

### 5. Scanning a repository without losing scope

Start with:

```bash
fast .scan lib app/services app/models --no-color
```

Then follow up with `.summary` or MCP method extraction only for the files the scan surfaces as relevant.

In local validation on `lib/fast`:

- reading the whole tree was about `29,144` estimated tokens
- `fast .scan lib/fast --no-color` was about `471`
- `.scan` plus summaries for the two most relevant files was about `1,654`

That is the main value of `.scan`: not just fewer tokens, but tighter scope control. The agent gets classification first, then chooses where to go deeper instead of committing too early to a large file.
