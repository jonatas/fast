# Empowering LLM Agents with Natural Language to Fast Patterns

Today I'm excited to announce a significant set of improvements to `fast`, specifically designed to bridge the gap between human reasoning (and LLM agents) and the technical precision of Ruby AST searching.

## The Problem: AST Patterns are Hard

Searching through code using AST patterns is incredibly powerful, but constructing the right S-expression can be daunting. Whether you're a human or an AI agent, getting the syntax just right—especially for complex queries—often involves a lot of trial and error.

## The Solution: NL-to-Fast Translation

We've introduced three new tools to solve this:

1.  **The `fast-pattern-expert` Skill**: A specialized Gemini CLI skill that provides deep guidance, syntax references, and few-shot examples for translating structural descriptions of Ruby code into valid `Fast` patterns.
2.  **`validate_fast_pattern` MCP Tool**: A new tool for our Model Context Protocol (MCP) server that allows agents to verify their generated patterns before executing them.
3.  **`--validate-pattern` CLI Flag**: A quick way for humans to check if their pattern syntax is correct, checking for balanced nesting and valid token types.

### Example in Action:
**Query:** "Find all classes that inherit from `BaseService` and have a `call` method."
**Pattern:** `[(class _ (const nil BaseService)) (def call)]`

## Robustness and Precision

We've also beefed up the core of `fast`:
- **Stricter Validation**: The `ExpressionParser` now tracks nesting levels and unconsumed tokens, providing helpful error messages instead of silently failing or returning partial matches.
- **Improved `...` Matcher**: The `...` literal now acts as a "rest-of-children" matcher when used at the end of a pattern, making it much easier to match methods with any number of arguments.
- **Graceful Degradation**: Multi-file scans (`.scan`) now degrade gracefully if a single file fails to parse, ensuring your reconnaissance isn't aborted by one unsupported syntax node.

## A Safer Release Workflow

On the operational side, I'm moving our gem release process to **GitHub Actions**. By releasing from a clean CI sandbox instead of my local machine, we ensure a much higher level of security and reproducibility. This move minimizes the risk of local environment contamination and provides a transparent, auditable path from source to RubyGems.

## Release 0.2.4

To celebrate these features, we are releasing version `0.2.4` today!

Happy searching!
