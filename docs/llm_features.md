# LLM/Agent Integration: Feature TODOs

As AI Agents and LLMs increasingly interact directly with codebases, `fast` is uniquely positioned to be the ultimate AST utility tool for AI context extraction. Below is a prioritized list of desired features and usability improvements specifically designed to make `fast` a robust backend for LLMs filtering large codebases.

## 1. JSON Structured Output (`--json`)
Currently, `fast` prints source output as plain text heavily reliant on `Fast.report`. LLMs and MCP (Model Context Protocol) servers expect strict, easily parseable structured data.
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
- **Value**: Perfect deterministic parsing for scripts, LLM tools, and MCP servers without needing to parse the `# file:line` headers.

## 2. Integrated Code Replacement (`--replace`)
LLMs often need to make precise string replacements in large files. By leveraging the AST, `fast` can target replacements more accurately than regex.
- **Requirement**: Add an automated way to replace nodes via CLI. For example: `fast replace "(def match?)" "def match?(node, env)" lib/`.
- **Value**: Enables agents to run structural find-and-replace deterministically across hundred-file codebases, removing the risk of regex false positives.

## 3. Context Lines (`-C`, `-A`, `-B` like Grep)
LLMs sometimes need the structural match but also a few surrounding lines of context (imports, class definitions, sibling methods) to make a correct edit.
- **Requirement**: Provide flags to include adjacent lines of source code or sibling AST nodes.

## 4. MCP Server Integration (Model Context Protocol)
With structural search out of the box, `fast` could be an incredible MCP server out of the box. 
- **Requirement**: Build a `fast-mcp` executable or a `fast mcp` command.
- **Tools to expose**:
  - `search_ruby_ast(pattern, dir)`: Search for a RuboCop AST pattern natively, returning JSON results.
  - `get_method(method_name, dir)`: Shortcut tool that extracts a specific method by name.
  - `get_class(class_name, dir)`: Shortcut tool that extracts the body of a specific class.
  - `replace_ruby_ast(pattern, replacement, dir)`: Structured search and replace.

## 5. Token Limit Awareness (`--max-tokens` / `--truncate`)
If a query matches an entire 3000-line class, it might blow out an LLM's context window.
- **Requirement**: A flag `fast "(class ...)" --max-tokens=1000` that will purposefully truncate the body of large AST nodes (perhaps retaining signatures but omitting block bodies) to fit within token boundaries.

## 6. Auto-disable ANSI colors for non-TTY
Currently, `fast` automatically tests `STDOUT.isatty`. LLM shells sometimes emulate TTYs or mishandle this detection, leading to ANSI color codes leaking into LLM context.
- **Requirement**: Ensure there's a foolproof way to bypass colorization natively if the `NO_COLOR` environment variable is set, or if an LLM is detected.
