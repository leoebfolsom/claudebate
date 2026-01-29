#!/bin/bash

# Claude Code Debate System
# Debates implementation approaches for software tasks
# Usage: ./code-debate.sh "task description" [--rounds N] [--time Nm] [--export FORMAT] [--context PATH] [--ralph]

set -e

# Defaults
MAX_ROUNDS=10
TIME_LIMIT_SECONDS=300  # 5 minutes
TASK=""
EXPORT_FORMAT=""  # Export format(s): md, html, or both (comma-separated)
CONTEXT_PATH=""   # Optional path to file or directory for codebase context
RALPH_MODE=false  # When true, debaters implement their approaches using Ralph/Claude

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --rounds)
            if [[ "$2" == "false" || "$2" == "none" ]]; then
                MAX_ROUNDS=0
            else
                MAX_ROUNDS="$2"
            fi
            shift 2
            ;;
        --time)
            TIME_ARG="$2"
            if [[ "$TIME_ARG" == "false" || "$TIME_ARG" == "none" ]]; then
                TIME_LIMIT_SECONDS=0
            elif [[ "$TIME_ARG" =~ ^([0-9]+)m$ ]]; then
                TIME_LIMIT_SECONDS=$((${BASH_REMATCH[1]} * 60))
            elif [[ "$TIME_ARG" =~ ^([0-9]+)s$ ]]; then
                TIME_LIMIT_SECONDS=${BASH_REMATCH[1]}
            else
                TIME_LIMIT_SECONDS="$TIME_ARG"
            fi
            shift 2
            ;;
        --export)
            EXPORT_FORMAT="$2"
            shift 2
            ;;
        --context)
            CONTEXT_PATH="$2"
            shift 2
            ;;
        --ralph)
            RALPH_MODE=true
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            TASK="$1"
            shift
            ;;
    esac
done

if [[ -z "$TASK" ]]; then
    echo "Code Debate: Explore implementation approaches through adversarial discussion"
    echo ""
    echo "Usage: $0 \"task/feature description\" [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --rounds N       Maximum number of debate rounds (default: 10)"
    echo "  --time Nm        Time limit in minutes (default: 5m)"
    echo "  --export FORMAT  Export transcript after debate ends"
    echo "                   FORMAT: md, html, or both (e.g., --export md,html)"
    echo "  --context PATH   File or directory to include as codebase context"
    echo "                   Helps debaters propose approaches grounded in your code"
    echo "  --ralph          Enable implementation mode: debaters actually implement"
    echo "                   their approaches using Ralph/Claude, judge evaluates real code"
    echo ""
    echo "Examples:"
    echo "  $0 \"Add user authentication to the API\" --rounds 5"
    echo "  $0 \"Refactor database layer for better testability\" --context ./src/db"
    echo "  $0 \"Implement caching strategy\" --time 3m --export md,html"
    echo "  $0 \"Add logging utility\" --ralph --context ./src"
    exit 1
fi

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
TRANSCRIPT="$SCRIPT_DIR/code_debate_${TIMESTAMP}.txt"
CONTROL="$SCRIPT_DIR/control.txt"

# Initialize files
echo "=== CODE DEBATE: $TASK ===" > "$TRANSCRIPT"
echo "Started: $(date)" >> "$TRANSCRIPT"
ROUNDS_DESC=$([[ $MAX_ROUNDS -gt 0 ]] && echo "$MAX_ROUNDS rounds" || echo "no round limit")
TIME_DESC=$([[ $TIME_LIMIT_SECONDS -gt 0 ]] && echo "$((TIME_LIMIT_SECONDS / 60))m $((TIME_LIMIT_SECONDS % 60))s" || echo "no time limit")
echo "Limits: $ROUNDS_DESC, $TIME_DESC" >> "$TRANSCRIPT"
if [[ -n "$CONTEXT_PATH" ]]; then
    echo "Context: $CONTEXT_PATH" >> "$TRANSCRIPT"
fi
echo "==========================================" >> "$TRANSCRIPT"
echo "" >> "$TRANSCRIPT"

# Clear control file
> "$CONTROL"

START_TIME=$(date +%s)
TURN=0
LAST_A=""
LAST_B=""

format_time() {
    local seconds=$1
    printf "%dm %ds" $((seconds / 60)) $((seconds % 60))
}

check_stop_conditions() {
    # Check control file for STOP
    if [[ -f "$CONTROL" ]] && grep -qi "STOP" "$CONTROL" 2>/dev/null; then
        echo ""
        echo ">>> STOP signal received. Ending debate gracefully."
        echo "" >> "$TRANSCRIPT"
        echo "=== DEBATE ENDED (STOP signal) ===" >> "$TRANSCRIPT"
        return 1
    fi

    # Check time limit
    local now=$(date +%s)
    local elapsed=$((now - START_TIME))
    if [[ $TIME_LIMIT_SECONDS -gt 0 ]] && [[ $elapsed -ge $TIME_LIMIT_SECONDS ]]; then
        echo ""
        echo ">>> Time limit reached. Ending debate."
        echo "" >> "$TRANSCRIPT"
        echo "=== DEBATE ENDED (time limit) ===" >> "$TRANSCRIPT"
        return 1
    fi

    # Check round limit
    local current_round=$(( (TURN + 1) / 2 ))
    if [[ $MAX_ROUNDS -gt 0 ]] && [[ $current_round -gt $MAX_ROUNDS ]]; then
        echo ""
        echo ">>> Round limit reached. Ending debate."
        echo "" >> "$TRANSCRIPT"
        echo "=== DEBATE ENDED (round limit) ===" >> "$TRANSCRIPT"
        return 1
    fi

    return 0
}

# Read context from file or directory
read_context() {
    local path="$1"
    local max_chars=10000  # Limit context size

    if [[ ! -e "$path" ]]; then
        echo "Error: Context path '$path' does not exist" >&2
        echo "Hint: Check the path or remove --context to run without codebase context" >&2
        return 1
    fi

    if [[ -f "$path" ]]; then
        # Single file
        head -c $max_chars "$path"
    elif [[ -d "$path" ]]; then
        # Directory: read key code files
        local content=""
        local total_chars=0

        # Find common code files
        while IFS= read -r -d '' file; do
            if [[ $total_chars -ge $max_chars ]]; then
                break
            fi
            local file_content
            file_content=$(head -c $((max_chars - total_chars)) "$file" 2>/dev/null || true)
            if [[ -n "$file_content" ]]; then
                content+="--- ${file#$path/} ---"$'\n'
                content+="$file_content"$'\n\n'
                total_chars=${#content}
            fi
        done < <(find "$path" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.jsx" -o -name "*.go" -o -name "*.rs" -o -name "*.java" -o -name "*.rb" -o -name "*.php" -o -name "*.c" -o -name "*.cpp" -o -name "*.h" \) -print0 2>/dev/null)

        echo "$content"
    fi
}

# Setup isolated sandbox directory for a debater's implementation
# Arguments: $1 = session name (e.g., "A" or "B")
# Returns: sandbox path via SANDBOX_PATH variable
setup_sandbox() {
    local session_name="$1"
    local sandbox_base="/tmp/code_debate_sandbox_$$"
    local sandbox_path="${sandbox_base}_${session_name}"

    # Create sandbox directory
    mkdir -p "$sandbox_path"

    # Copy context if provided
    if [[ -n "$CONTEXT_PATH" && -e "$CONTEXT_PATH" ]]; then
        if command -v rsync &>/dev/null; then
            # Use rsync with .git exclusion
            rsync -a --exclude='.git' "$CONTEXT_PATH/" "$sandbox_path/" 2>/dev/null || {
                # Fallback to cp if rsync fails
                cp -R "$CONTEXT_PATH"/* "$sandbox_path/" 2>/dev/null || true
                # Remove .git if it was copied
                rm -rf "$sandbox_path/.git" 2>/dev/null || true
            }
        else
            # Fallback to cp if rsync unavailable
            cp -R "$CONTEXT_PATH"/* "$sandbox_path/" 2>/dev/null || true
            # Remove .git if it was copied
            rm -rf "$sandbox_path/.git" 2>/dev/null || true
        fi
    fi

    # Initialize fresh git repo for clean diff tracking
    (
        cd "$sandbox_path"
        git init -q
        git add -A 2>/dev/null || true
        git commit -q -m "Initial state" 2>/dev/null || true
    )

    # Return sandbox path via variable
    SANDBOX_PATH="$sandbox_path"
    echo "$sandbox_path"
}

# Track sandbox directories for cleanup
SANDBOX_DIRS=()

# Get context content if path specified
CONTEXT_CONTENT=""
if [[ -n "$CONTEXT_PATH" ]]; then
    CONTEXT_CONTENT=$(read_context "$CONTEXT_PATH")
    if [[ -z "$CONTEXT_CONTENT" ]]; then
        echo "Warning: No code files found in '$CONTEXT_PATH' (continuing without context)"
    else
        echo "Loaded context from: $CONTEXT_PATH"
    fi
fi

build_prompt() {
    local session="$1"
    local is_first="$2"
    local opponent_arg="$3"

    local now=$(date +%s)
    local elapsed=$((now - START_TIME))
    local remaining=0
    if [[ $TIME_LIMIT_SECONDS -gt 0 ]]; then
        remaining=$((TIME_LIMIT_SECONDS - elapsed))
        if [[ $remaining -lt 0 ]]; then remaining=0; fi
    fi

    local current_round=$(( (TURN / 2) + 1 ))
    local turns_remaining=0
    if [[ $MAX_ROUNDS -gt 0 ]]; then
        turns_remaining=$(( (MAX_ROUNDS - current_round) * 2 + 1 ))
        if [[ "$is_first" == "false" ]]; then
            turns_remaining=$((turns_remaining - 1))
        fi
    fi

    local status_line="Turn $((TURN + 1))"
    if [[ $MAX_ROUNDS -gt 0 ]]; then
        status_line="$status_line of $((MAX_ROUNDS * 2))"
    fi
    if [[ $TIME_LIMIT_SECONDS -gt 0 ]]; then
        status_line="$status_line | $(format_time $remaining) of $(format_time $TIME_LIMIT_SECONDS) remaining"
    fi

    local pacing_hint=""
    if [[ $MAX_ROUNDS -gt 0 ]] && [[ $turns_remaining -le 2 ]]; then
        pacing_hint="- FINAL TURNS: Summarize your approach and address remaining concerns"
    elif [[ $TIME_LIMIT_SECONDS -gt 0 ]] && [[ $remaining -lt 60 ]]; then
        pacing_hint="- TIME RUNNING LOW: Summarize your key design decisions"
    fi

    local context_section=""
    if [[ -n "$CONTEXT_CONTENT" ]]; then
        context_section="EXISTING CODEBASE CONTEXT:
$CONTEXT_CONTENT

"
    fi

    local role_section=""
    if [[ -n "$opponent_arg" ]]; then
        role_section="You are $session. Propose a DIFFERENT implementation approach than your opponent.

OPPONENT'S APPROACH:
$opponent_arg

"
    else
        role_section="You are $session. Propose a clear implementation approach for this task.

"
    fi

    cat <<EOF
IMPLEMENTATION TASK: $TASK
STATUS: $status_line

${context_section}${role_section}INSTRUCTIONS:
- Propose a specific implementation approach
- Include key design decisions and trade-offs you're making
- Be concrete: mention file structure, function signatures, data flow where relevant
- Include pseudocode or code snippets when they clarify your approach
- Acknowledge trade-offs of your approach honestly
- Keep response focused (2-4 paragraphs plus any code examples)
$pacing_hint
EOF
}

run_turn() {
    local session="$1"
    local is_first="$2"
    local opponent_arg="$3"

    local prompt
    prompt=$(build_prompt "$session" "$is_first" "$opponent_arg")

    echo ""
    echo ">>> $session - Turn $((TURN + 1))..."

    # Run claude and capture output
    local response
    response=$(claude -p "$prompt" 2>/dev/null) || {
        echo "Error running claude CLI"
        return 1
    }

    # Append to transcript
    echo "--- $session - Turn $((TURN + 1)) ---" >> "$TRANSCRIPT"
    echo "$response" >> "$TRANSCRIPT"
    echo "" >> "$TRANSCRIPT"

    # Display response
    echo ""
    echo "$response"
    echo ""

    # Return the response via a global variable (bash limitation)
    LAST_RESPONSE="$response"
}

echo "Starting code debate: $TASK"
echo "Limits: $ROUNDS_DESC, $TIME_DESC"
if [[ -n "$CONTEXT_PATH" ]]; then
    echo "Context: $CONTEXT_PATH"
fi
echo "To stop early: echo 'STOP' > $CONTROL"
echo ""

# Main debate loop
while true; do
    # Check stop conditions before each turn
    if ! check_stop_conditions; then
        break
    fi

    # Session A turn
    run_turn "Session A" "true" "$LAST_B"
    LAST_A="$LAST_RESPONSE"
    TURN=$((TURN + 1))

    # Check stop conditions
    if ! check_stop_conditions; then
        break
    fi

    # Session B turn
    run_turn "Session B" "false" "$LAST_A"
    LAST_B="$LAST_RESPONSE"
    TURN=$((TURN + 1))
done

# Judge the debate
echo ""
echo ">>> Judge evaluating implementation approaches..."

DEBATE_CONTENT=$(cat "$TRANSCRIPT")
JUDGE_PROMPT=$(cat <<EOF
You are a senior software engineer judging a code implementation debate. Your goal is to provide an actionable recommendation that a developer can immediately use to start implementing.

IMPLEMENTATION TASK: $TASK

FULL TRANSCRIPT:
$DEBATE_CONTENT

Provide your evaluation in this format:

## Approach Summaries
**Session A**: [2-3 sentence summary of their approach]
**Session B**: [2-3 sentence summary of their approach]

## Engineering Evaluation

Rate each approach (Strong/Adequate/Weak) with brief justification:

| Criterion | Session A | Session B |
|-----------|-----------|-----------|
| **Simplicity** (ease of understanding, minimal complexity) | | |
| **Maintainability** (ease of modification, clear boundaries) | | |
| **Testability** (unit test coverage, mockability, isolation) | | |
| **Performance** (efficiency, scalability concerns) | | |
| **Extensibility** (handles future requirements, flexibility) | | |

## Risk Analysis

**Session A risks**:
- Edge cases handled: [list]
- Edge cases missed: [list]
- Potential failure modes: [list]

**Session B risks**:
- Edge cases handled: [list]
- Edge cases missed: [list]
- Potential failure modes: [list]

## Verdict

**RECOMMENDED: Session [A/B]**

**Key reasons** (top 3):
1. [Most important reason]
2. [Second reason]
3. [Third reason]

## Implementation Roadmap

To implement the winning approach:

1. **Start with**: [First file/component to create or modify]
2. **Core implementation**: [Key functions/classes to build]
3. **Data flow**: [How data moves through the system]
4. **Testing strategy**: [What to test and how]
5. **Gotchas to watch**: [Common pitfalls to avoid]

**Suggested file structure** (if applicable):
\`\`\`
[directory/file layout]
\`\`\`

**Key code patterns to use**:
[Any specific patterns, interfaces, or approaches recommended]

---
Judge based on engineering merit. The developer should be able to start coding immediately after reading this verdict.
EOF
)

VERDICT=$(claude -p "$JUDGE_PROMPT" 2>/dev/null) || {
    echo "Error running judge"
    exit 1
}

echo "" >> "$TRANSCRIPT"
echo "=== JUDGE'S VERDICT ===" >> "$TRANSCRIPT"
echo "$VERDICT" >> "$TRANSCRIPT"

echo ""
echo "$VERDICT"
echo ""

# Source shared export functions
source "$SCRIPT_DIR/export_functions.sh"

# Auto-export if --export flag was set
if [[ -n "$EXPORT_FORMAT" ]]; then
    echo ">>> Exporting transcript..."

    # Check for md export
    if [[ "$EXPORT_FORMAT" == "md" || "$EXPORT_FORMAT" == *"md"* ]]; then
        md_file=$(export_to_md "$TRANSCRIPT")
        echo "Exported to Markdown: $md_file"
    fi

    # Check for html export
    if [[ "$EXPORT_FORMAT" == "html" || "$EXPORT_FORMAT" == *"html"* ]]; then
        html_file=$(export_to_html "$TRANSCRIPT")
        echo "Exported to HTML: $html_file"
    fi

    echo ""
fi

echo ""
echo "Code debate complete! Transcript saved to: $TRANSCRIPT"
echo "Total turns: $TURN"
