# Fast Gains: Tracking Search Efficiency

Fast includes a "Gains" feature that tracks the efficiency of your code searches and explorations. It measures the amount of data searched versus the amount of data actually reported to quantify the "savings" in terms of context and manual effort.

This is particularly useful when using Fast as a tool for LLMs and Agents (via the [MCP Server](mcp_tutorial.md)), where minimizing unnecessary context is crucial for performance and cost.

## How it Works

The Gains feature monitors three main metrics during a search:

1.  **Bytes Searched**: The total size of all files that Fast scanned.
2.  **Bytes Reported**: The size of the actual results (AST nodes, source code, or summaries) that were returned to the user or agent.
3.  **Savings**: The difference between Bytes Searched and Bytes Reported, often expressed as a percentage.

### Example

If you search a project with 10MB of source code and Fast returns a specific 1KB method definition, the "gain" is approximately 9.99MB, or a 99.9% reduction in the data you had to process manually.

## Usage

### Viewing the Report

You can view your accumulated gains history using the `.gains` command:

```bash
fast .gains
```

This will display a summary of:
- Total bytes searched and reported.
- Total files scanned and matched.
- Total savings (in bytes and percentage).
- A bar chart of recent savings history.

### Filtering Results

Fast categorizes gains into two groups:
- **CLI**: Searches performed directly through the command-line interface.
- **MCP**: Searches performed by an LLM or Agent via the Model Context Protocol server.

You can filter the report to see only one of these:

```bash
fast .gains cli
# or
fast .gains mcp
```

## Configuration

Gains tracking is enabled by default in some contexts (like the MCP server) but can be controlled via environment variables or programmatically.

### Environment Variable

To disable gains tracking across all contexts (CLI and MCP), set the `FAST_GAINS` environment variable to `0`:

```bash
export FAST_GAINS=0
```

### Ruby API

To enable or disable tracking in Ruby code:

```ruby
Fast.enable_gain_track!
Fast.disable_gain_track!
```

## Storage

Gains data is stored locally on your machine:
- **Directory**: `~/.fast/`
- **History File**: `~/.fast/gains.json`

The system uses temporary files for each run and consolidates them into the main history file when you run the `.gains` command. This ensures that concurrent searches (e.g., from multiple agents) don't lose data or cause file locks.

To keep the history file manageable, Fast only keeps the full report content for the last 5 runs, while retaining the metrics for all historical runs.

## Why Track Gains?

- **Quantify Value**: See how much manual "grepping" and reading Fast is saving you.
- **Optimize Agent Prompts**: High "Bytes Reported" might indicate that your agent's search patterns are too broad and could be refined to save tokens.
- **Monitor Project Growth**: Track how your project's size affects search performance over time.
