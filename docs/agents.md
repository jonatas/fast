# Using Fast for LLMs and Agents

Welcome, Agent! `fast` is an extremely powerful AST-based (Abstract Syntax Tree) code search tool for Ruby (and optionally SQL). As an LLM, you are highly constrained by context tokens. Using traditional `grep` often returns fragmented, truncated, or excessively noisy text. `fast` allows you to semantically query Ruby codebases and retrieve exactly the structured syntax you need, saving tokens and improving your code reasoning capabilities.

## Why use `fast` over `grep`?

- **Precision**: You can search for syntactic constructs (e.g., classes, method definitions, specific method calls) rather than just substrings.
- **Context Preservation**: `fast` inherently understands the bounds of a method or block. It will print the entire body of the AST node matched, not just the single line containing the keyword.
- **Token Efficiency**: Get only the function or class you want, instead of 100 lines of regex false positives.
- **File and Line Locality**: Outcomes are directly prefixed with the file and line number by default (`# file/path.rb:123`), making it trivial to know exactly where the code is located for further editing or patching.

## Essential CLI Flags for Agents

To maximize reliability and reduce context noise, use these flags when invoking `fast` from the command line:

- `--no-color`: **CRITICAL**. Always use this flag to strip ANSI escape codes formatting out of the output. TTY color codes consume unnecessary tokens and break markdown parsing.
- `--headless`: Omits the `# filename.rb:line` header if you only want the raw code snippet and don't care about the location.
- `--bodyless`: Omits the code block body and only shows the matched headers (useful for finding *where* something is without reading *what* it is).
- `--ast`: Prints the S-expression representation of the matching nodes. Outstanding when you need to understand the internal AST structure of a complex ruby construct to construct more advanced `fast` queries or RuboCop node patterns.

## Query Examples

### Finding Method Definitions
Instead of `grep -rn "def process" .`:
```bashfast "(def process)" app/ lib/```

## Advanced Search
You can use `^` to search upstream (e.g. parent nodes) or use `{}` for unions:
```bash
# Find classes that contain a specific method
fast "^(def my_specific_method)" app/

# Find both `def_node_matcher` and `def_node_search` usage
fast "(send nil {def_node_matcher def_node_search})" lib/
```

## Best Practices for LLM Context

1. **Initial Recon**: When entering a new file or directory, if you know the name of the function, use `fast "(def <name>)" <path> --no-color`.
2. **Finding References**: To find where a method is called, use `fast "(send _ :<name>)" <path> --no-color`.
3. **AST Inspection**: If you need to manipulate a complex file, you can output the AST of a specific method to construct a patch: `fast "(def <name>)" <file> --ast --no-color`.
