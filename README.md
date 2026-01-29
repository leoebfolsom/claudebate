# claudebate

Automated debates between two Claude Code sessions using file-based communication, with a third Claude Code session as the Judge.

## Prerequisites

- [Claude Code](https://claude.ai/code) installed and authenticated

## Quick Start

```bash
./debate.sh "What ice cream flavor really hits the spot?"
```

## How It Works

1. The script invokes `claude -p` for each turn, alternating between Session A and Session B
2. Each session receives the topic, time/turn status, and opponent's last argument
3. Responses are appended to the transcript
4. Debate ends when round limit, time limit, or STOP signal is reached
5. A third Claude (the Judge) evaluates the full debate and declares a winner

## Stopping a Debate

**Graceful stop** (finishes current turn):
```bash
echo "STOP" > control.txt
```

**Immediate stop**: `Ctrl+C`

## Output Files

- `transcript_YYYY-MM-DD_HHMMSS.txt` - Full debate history (new file each run)
- `transcript_YYYY-MM-DD_HHMMSS.md` - Markdown export (if `--export` used)
- `transcript_YYYY-MM-DD_HHMMSS.html` - Styled HTML export (if `--export` used)
- `control.txt` - Write "STOP" here to end early

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--rounds N` | Maximum number of rounds | 10 |
| `--rounds false` | No round limit | |
| `--time Nm` | Time limit (e.g., `5m`, `300s`) | 5m |
| `--time false` | No time limit | |
| `--export FORMAT` | Export transcript when done (`md`, `html`, or `md,html`) | none |

```bash
# Custom limits
./debate.sh "Who is the greatest baseball player of all time?" --rounds 5 --time 3m

# No round limit (debate runs until time expires)
./debate.sh "Is OOP overrated?" --time 10m --rounds false

# No time limit (debate runs until rounds complete)
./debate.sh "Are we in an AI bubble?" --rounds 8 --time false

# Export to Markdown and HTML when debate ends
./debate.sh "Tabs vs spaces" --export md,html
```

## Exporting Existing Transcripts

Use `export.sh` to export transcripts after a debate has completed:

```bash
# Export to both formats
./export.sh transcript_2026-01-27_145526.txt --format both

# Export to Markdown only
./export.sh transcript_2026-01-27_145526.txt --format md

# Export to HTML only
./export.sh transcript_2026-01-27_145526.txt --format html
```

## Code Debate Mode

Use `code-debate.sh` to explore implementation approaches for software tasks through adversarial discussion. Instead of debating opinions, two Claude sessions propose competing technical approaches, and a judge evaluates them using software engineering criteria.

### When to Use Code Debate

- **Before implementing a complex feature** - Explore trade-offs between approaches
- **When refactoring** - Compare different architectural patterns
- **For technical decisions** - Database schemas, API designs, caching strategies
- **When stuck** - Get fresh perspectives on a problem

### Usage

```bash
./code-debate.sh "task description" [OPTIONS]
```

| Flag | Description | Default |
|------|-------------|---------|
| `--rounds N` | Maximum number of rounds | 10 |
| `--time Nm` | Time limit (e.g., `5m`, `300s`) | 5m |
| `--export FORMAT` | Export transcript (`md`, `html`, or `md,html`) | none |
| `--context PATH` | File or directory for codebase context | none |
| `--ralph` | Enable implementation mode (see below) | off |

### The --context Flag

The `--context` flag grounds the debate in your actual codebase:

```bash
# Provide a specific file for context
./code-debate.sh "Add caching to the user service" --context ./src/services/user.ts

# Provide a directory (reads common code files: .sh, .py, .js, .ts, etc.)
./code-debate.sh "Refactor database layer" --context ./src/db

# Context helps debaters propose approaches that fit your existing patterns
./code-debate.sh "Add authentication middleware" --context ./src/middleware
```

When to use `--context`:
- When approaches should follow existing code patterns
- When the task involves modifying existing code
- When integration with current architecture matters

When to skip `--context`:
- Greenfield projects or standalone utilities
- General design discussions not tied to specific code
- When you want approaches unconstrained by current implementation

### The --ralph Flag (Implementation Mode)

Standard code debates compare *proposals* - theoretical approaches that debaters describe and defend. With `--ralph`, debates compare *actual implementations* - each debater's approach is implemented in a sandboxed copy of your codebase, and the judge evaluates real code diffs.

```bash
# Standard mode: debaters propose approaches, judge evaluates proposals
./code-debate.sh "Add input validation to the form" --context ./src/forms

# Ralph mode: debaters implement approaches, judge evaluates actual code
./code-debate.sh "Add input validation to the form" --context ./src/forms --ralph
```

**How it works:**

1. Each debater proposes an approach (same as standard mode)
2. A sandboxed copy of your codebase is created for each debater
3. The approach is actually implemented using Claude (or Ralph if available)
4. The resulting git diff is captured
5. The judge evaluates both implementations using code review criteria

**Judge evaluation in ralph mode:**

| Criterion | What the Judge Evaluates |
|-----------|--------------------------|
| **Code Quality** | Readability, style consistency, best practices |
| **Correctness** | Does the implementation actually solve the problem? |
| **Completeness** | Are all requirements addressed? Edge cases handled? |
| **Simplicity** | Is the solution appropriately minimal? |
| **Maintainability** | Will this be easy to modify and extend? |
| **Testability** | Can this code be effectively unit tested? |

**When to use --ralph:**

- When you want to see actual code, not just descriptions
- When implementation details matter more than high-level design
- When you want the judge to evaluate real trade-offs in code

**When to skip --ralph:**

- For architectural discussions where code isn't the focus
- When speed matters (ralph mode takes significantly longer)
- For exploratory debates where you're still defining the problem

### Example: Realistic Software Task

```bash
./code-debate.sh "Implement rate limiting for the API" --context ./src/api --rounds 4 --export md
```

This will:
1. Load relevant code from `./src/api` to understand existing patterns
2. Have Session A propose one rate limiting approach (e.g., token bucket with Redis)
3. Have Session B propose a different approach (e.g., sliding window with in-memory store)
4. Continue for 4 rounds as each refines and defends their approach
5. Judge evaluates using engineering criteria and recommends the better approach
6. Export the transcript to Markdown for reference

### How the Judge Evaluates

Unlike opinion debates where the judge picks a "winner" based on argumentation, the code debate judge evaluates approaches as a **senior software engineer** using these criteria:

| Criterion | What the Judge Looks For |
|-----------|--------------------------|
| **Simplicity** | Ease of understanding, minimal complexity |
| **Maintainability** | Clear boundaries, ease of modification |
| **Testability** | Unit test coverage, mockability, isolation |
| **Performance** | Efficiency, scalability concerns |
| **Extensibility** | Handles future requirements, flexibility |

The judge also provides:
- **Risk Analysis**: Edge cases handled or missed, potential failure modes
- **Implementation Roadmap**: Concrete steps to start coding
- **Suggested file structure** and code patterns

The verdict is designed to be **actionable** - you should be able to start implementing immediately after reading it.

### Output Files

- `code_debate_YYYY-MM-DD_HHMMSS.txt` - Full debate transcript
- `code_debate_YYYY-MM-DD_HHMMSS.md` - Markdown export (if `--export` used)
- `code_debate_YYYY-MM-DD_HHMMSS.html` - HTML export (if `--export` used)
