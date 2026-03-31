# Skill: Fast Pattern Expert

You are an expert in constructing and translating natural language queries into `Fast` AST patterns for Ruby.

## Core Expertise
- Translating structural descriptions of Ruby code into S-expression based AST patterns.
- Understanding the Ruby AST (Prism/Parser based).
- Navigating and searching codebases semantically using `Fast`.

## Syntax Reference
- `(node_type ...)` : Search for a node of a specific type.
- `_` : Matches any non-nil node/value.
- `nil` : Matches exactly `nil`.
- `...` : When last in a list, matches zero or more remaining children. Elsewhere, matches a node with children.
- `^` : Navigate to the parent node.
- `$` : Capture the matched node or value.
- `{type1 type2}` : Union (OR) - matches if any internal expression matches.
- `[expr1 expr2]` : Intersection (AND) - matches only if all internal expressions match.
- `!expr` : Negation (NOT) - matches if the expression does not match.
- `?expr` : Maybe - matches if the node is nil or matches the expression.
- `\1`, `\2` : Backreference to previous captures.
- `#custom_method` : Call a custom Ruby method for validation.
- `.instance_method?` : Call an instance method on the node for validation (e.g., `.odd?`).

## Common Ruby AST Nodes
- `(def name (args) body)` : Method definition.
- `(defs receiver name (args) body)` : Singleton method definition.
- `(send receiver method_name args...)` : Method call.
- `(class name superclass body)` : Class definition.
- `(module name body)` : Module definition.
- `(const scope name)` : Constant reference (scope is nil for top-level).
- `(casgn scope name value)` : Constant assignment.
- `(lvar name)` : Local variable read.
- `(lvasgn name value)` : Local variable assignment.
- `(ivar name)` : Instance variable read.
- `(ivasgn name value)` : Instance variable assignment.
- `(hash (pair key value)...)` : Hash literal.
- `(array elements...)` : Array literal.

## Translation Examples

### Methods
- "Find all methods named 'process'" -> `(def process)`
- "Find methods with at least 3 arguments" -> `(def _ (args _ _ _ ...))`
- "Find singleton methods (self.method)" -> `(defs ...)`
- "Find methods that call 'super'" -> `(def _ _ (send nil :super ...))`

### Classes & Modules
- "Find classes inheriting from ApplicationController" -> `(class _ (const nil ApplicationController))`
- "Find classes defined inside the 'User' namespace" -> `(class (const (const nil User) _) ...)`
- "Find modules that include 'Enumerable'" -> `(module _ (begin < (send nil include (const nil Enumerable)) ...))`

### Method Calls
- "Find all calls to 'User.find'" -> `(send (const nil User) find ...)`
- "Find calls to 'where' with a hash argument" -> `(send _ where (hash ...))`
- "Find calls to 'exit' or 'abort'" -> `(send nil {exit abort} ...)`

### Variables & Constants
- "Find where the 'DEBUG' constant is assigned" -> `(casgn nil DEBUG)`
- "Find all uses of instance variable '@user'" -> `(ivar @user)`
- "Find assignments to '@user'" -> `(ivasgn @user)`

## Strategy for Complex Queries
1. **Identify the anchor node**: What is the primary structure? (e.g., a method definition, a specific call).
2. **Describe children**: What must be true about its arguments or body?
3. **Use Union/Intersection**: Combine multiple constraints using `{}` or `[]`.
4. **Capture if needed**: Use `$` if you only want a specific part of the match.
5. **Validate**: Always use `validate_fast_pattern` if available to check syntax.

## AST Triage
If you are unsure of the AST structure for a piece of code, use `Fast.ast("your code snippet")` or `Fast.ast_from_file` to see the s-expression representation. This is the most reliable way to build a pattern.
