# MCP Experiment Feedback: `RSpec/WeakFormatMatcher`

Date: 2026-04-14

## Goal

Use `fast-mcp` and `run_fast_experiment` to validate a refactoring that turns weak controller-spec matchers like:

```ruby
post_with user, :create, params: params
expect(response).to render_template('denied')
```

into JSON-aware assertions like:

```ruby
post_with user, :create, params: params, format: :json
expect(response).to have_http_status(:forbidden)
```

The intent is to catch specs that accidentally exercise `ApplicationController#permission_denied` HTML behavior instead of the real JSON code path.

## What Worked

- `fast-mcp` was very useful for structural search.
- It accurately found the inline weak matcher shape in a smaller target file:
  `spec/controllers/invoice_payments_controller_spec.rb`
- A narrowed pattern targeting only `post_with` and `delete_with` plus `render_template('denied')` found 8 exact candidates in that file.
- Running the generated experimental files with the real spec command showed that all 8 individual rewrites passed.
- After manually applying those 8 rewrites, the file still passed:

```bash
POSTGRES_HOST=localhost POSTGRES_USER=root POSTGRES_PASSWORD=root \
  /Users/jonatas/.rbenv/shims/bundle exec rspec --fail-fast spec/controllers/invoice_payments_controller_spec.rb
```

Result:
- 84 examples, 0 failures

## What Failed

### 1. `fast-mcp` gains path is not sandbox-friendly

When running under a restricted environment, `fast-mcp` attempted to write gains files under:

```text
/Users/jonatas/.fast/gains-....json
```

and failed with:

```text
Operation not permitted @ rb_sysopen - /Users/jonatas/.fast/gains-....json
```

Workaround used:
- override `HOME` to a writable temp directory, e.g. `/tmp/codex-fastmcp`

Suggested fix:
- allow disabling gains persistence for MCP runs
- or allow configuring the gains directory explicitly
- or rescue gains write failures and continue tool execution

### 2. MCP experiments inherit the wrong Bundler context

The MCP server was started from the `fast` repo, so `run_fast_experiment` inherited `fast`'s `BUNDLE_GEMFILE`.
That broke policy commands that were intended to run in the target Rails app.

Observed failure while validating generated spec files:

```text
LoadError: cannot load such file -- dotenv
```

The generated spec file was correct; the policy subprocess was running under the wrong bundle.

Workaround used:
- pin the target app bundle in the policy command explicitly:

```bash
BUNDLE_GEMFILE=/path/to/target/Gemfile bundle exec rspec --fail-fast {file}
```

Suggested fix:
- add optional `policy_env` support to `run_fast_experiment`
- or run the policy in the target file's project directory with a clean environment
- or expose a first-class `cwd`/`env` option for MCP experiment execution

### 3. The edit block capture shape is easy to get wrong

For a search like:

```ruby
(block ... $(send ...) $(send ...))
```

captures arrived wrapped such that the edit block initially received arrays instead of direct nodes.
This produced errors like:

```text
undefined method `loc' for an instance of Array
```

Workaround used:
- flatten captures inside the edit block

```ruby
request_call, assertion = captures.flatten
```

Suggested fix:
- document the capture shape more explicitly in MCP docs
- or normalize captures before yielding to the experiment edit block
- or add a helper/debug mode to print capture classes and matched code

### 4. The combination/finalization logic did not apply the validated winners

This was the most important failure.

Observed behavior:
- 8 individual weak-matcher rewrites were identified
- generated files like `experiment_1_invoice_payments_controller_spec.rb` through `experiment_8_...` all passed
- but `run_fast_experiment` finished with:

```text
No changes were made to the file.
```

So the experiment proved the survivors, but did not finalize any change back to the original file.

This made the experiment useful as a validator, but not as an end-to-end refactoring tool.

### 5. Combination strategy is still too naive for real spec files

The current algorithm is:
- round 1: test each occurrence individually
- round 2: try all individually successful replacements together
- round 3+: try pair combinations and some follow-up combinations

This has a few problems for real-world controller specs:
- large files still blow up quickly
- the pairwise fallback is expensive
- for additive, independent refactors, pairwise recombination is unnecessary once individual survivors are known
- even when individual mutations are all valid, the final file may still not be applied because the bookkeeping/finalization path is brittle

## Recommended Algorithm Changes

### 1. Add a progressive strategy instead of pairwise-first fallback

For experiments like this one, a better strategy would be:

1. Run all individual mutations.
2. Keep the list of individually successful indices.
3. Try one combined mutation of all individual survivors.
4. If combined succeeds, apply it and stop.
5. If combined fails, bisect or chunk the survivors instead of generating all pairs.
6. If chunks succeed, merge successful chunks progressively.

This is much closer to how an engineer would reason about additive spec rewrites.

### 2. Add a mode that can apply individual survivors directly

For highly local, independent edits, there should be a mode like:

- `strategy: :apply_individual_survivors`
- or `finalize: :merge_successful_singles`

This would have solved the `WeakFormatMatcher` case immediately.

The experiment had already demonstrated that each of the 8 target edits was safe in the file.
The tool should be able to merge those exact successful individual edits into the original file without requiring a successful combination search.

### 3. Track and expose round results explicitly

The MCP response should include structured data like:

- occurrences found
- successful individual indices
- failed individual indices
- combinations attempted
- combinations that passed
- final chosen combination
- whether the original file was rewritten

Right now, too much of the decision process is hidden in captured stdout.

### 4. Add a dry summary mode for experiments

A useful MCP addition would be:

- search
- run the policy for each individual candidate
- return a summary of which edits are safe
- do not try to combine or write the final file

That would be ideal for research and for building confidence before mutation.

## Pattern Feedback Specific To `WeakFormatMatcher`

The broad pattern from research works for discovery, but for experiments it should be narrowed aggressively.

Good narrowing dimensions:
- only inline request helpers, not subject-based request helpers
- only `render_template('denied')`
- only actions known or suspected to be JSON-only
- start with one small file
- avoid `get_with` if the file mixes `format: :dialog` or HTML endpoints in the same action family

In practice, the first successful target here was:
- `post_with` and `delete_with`
- inline `it` blocks
- exact denied assertion
- one file: `invoice_payments_controller_spec.rb`

That was enough to validate the core idea without starting at `InvoicesController` scale.

## Environment Friction Observed During This Run

These were not `fast` logic bugs, but they matter for MCP usability:

- the target worktree was incomplete and needed folder wiring fixes before Rails could boot
- the spec policy required DB access and therefore elevated permissions in the host environment
- duplicate constant warnings appeared because the worktree mixed local files with linked app subtrees

This reinforces that `run_fast_experiment` should expect messy real-world environments and make it easier to inspect, control, and recover from environment setup issues.

## Concrete Next Steps For `fast`

1. Make gains logging optional or configurable for MCP.
2. Add `cwd` and `env` support to `run_fast_experiment`.
3. Expose structured experiment results in MCP responses instead of only a log blob.
4. Add a strategy that can finalize by merging successful single replacements.
5. Replace pairwise fallback with chunking/bisection for large survivor sets.
6. Add tests covering the case where:
   - several individual replacements pass
   - no final rewrite is applied today
   - the correct behavior is to merge those successful singles
7. Add documentation showing how to run experiments against another repo with explicit `BUNDLE_GEMFILE`, `HOME`, and policy env.

## Most Important Takeaway

`fast-mcp` already provides real value for experiment-driven refactoring research.
The search and validation parts worked.

The current weak point is finalization:
- it can prove that multiple individual edits are safe
- but still fail to produce the rewritten original file

For `WeakFormatMatcher`, fixing that finalization path would likely make the approach immediately useful across a much larger set of controller specs.
