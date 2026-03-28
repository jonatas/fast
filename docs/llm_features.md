# LLM/Agent Integration: Feature TODOs

`fast` already ships both a CLI and an MCP server for LLM-oriented workflows. This page tracks the remaining work to make those integrations stronger and easier to adopt.

## Existing strengths

Before the remaining gaps, there are already two high-value agent workflows available today:

- `.summary` for single-file structural reconnaissance
- `.scan` for multi-file repo triage with bounded output

In local validation on `lib/fast`:

- full tree read: about `29,144` estimated tokens
- `.scan lib/fast --no-color`: about `471`
- `.scan` plus summaries for two relevant files: about `1,654`

That means the current summary-first workflow can already reduce both token use and exploration noise substantially, even before JSON output exists.

## 1. JSON Structured Output (`--json`)
Currently, the CLI prints source output as plain text heavily reliant on `Fast.report`. The MCP server already returns structured JSON-like payloads, but the CLI still lacks a native machine-friendly mode.
- **Requirement**: Add a `--json` flag to `fast`.
- **Expected Output**: A JSON array of matches. Each element should include:
  ```json
  [
    {
      "file": "lib/fast.rb",
      "line_start": 439,
      "line_end": 441,
      "code": "def match?(node)\n  match_recursive(valuate(token), node)\nend",
      "ast_sexp": "(def :match? (args (arg :node)) (send nil :match_recursive ...))"
    }
  ]
  ```
- **Value**: Perfect deterministic parsing for scripts and LLM tools without needing to parse the `# file:line` headers.

## 2. Integrated Code Replacement (`--replace`)
LLMs often need to make precise string replacements in large files. By leveraging the AST, `fast` can target replacements more accurately than regex.
- **Requirement**: Add an automated way to replace nodes via CLI. For example: `fast replace "(def match?)" "def match?(node, env)" lib/`.
- **Value**: Enables agents to run structural find-and-replace deterministically across hundred-file codebases, removing the risk of regex false positives.
- **Current advantage**: The existing Ruby rewrite path already validates the rewritten output and rejects invalid Ruby before returning or writing it.

## 3. Context Lines (`-C`, `-A`, `-B` like Grep)
LLMs sometimes need the structural match but also a few surrounding lines of context (imports, class definitions, sibling methods) to make a correct edit.
- **Requirement**: Provide flags to include adjacent lines of source code or sibling AST nodes.

## 4. MCP Server Integration (Model Context Protocol)
`fast-mcp` already exists and exposes structural search and rewrite tools over stdio.
- **Requirement**: Improve host integration guidance and expand tool coverage where needed.
- **Tools to expose**:
  - `search_ruby_ast(pattern, dir)`: Search for a RuboCop AST pattern natively, returning JSON results.
  - `get_method(method_name, dir)`: Shortcut tool that extracts a specific method by name.
  - `get_class(class_name, dir)`: Shortcut tool that extracts the body of a specific class.
  - `replace_ruby_ast(pattern, replacement, dir)`: Structured search and replace.
- **Next gaps**:
  - Add examples for Codex, Claude Desktop, and other MCP-capable hosts.
  - Consider exposing resources/templates only if they add value beyond tools.
  - Improve scoping for `ruby_method_source` with `class_name` so it is lexical, not file-level.

## 5. Token Limit Awareness (`--max-tokens` / `--truncate`)
If a query matches an entire 3000-line class, it might blow out an LLM's context window.
- **Requirement**: A flag `fast "(class ...)" --max-tokens=1000` that will purposefully truncate the body of large AST nodes (perhaps retaining signatures but omitting block bodies) to fit within token boundaries.

## 6. Auto-disable ANSI colors for non-TTY
Currently, `fast` automatically tests `STDOUT.isatty`. LLM shells sometimes emulate TTYs or mishandle this detection, leading to ANSI color codes leaking into LLM context.
- **Requirement**: Ensure there's a foolproof way to bypass colorization natively if the `NO_COLOR` environment variable is set, or if an LLM is detected.
