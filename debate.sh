#!/bin/bash

# Claude Code Debate System
# Usage: ./debate.sh "topic" [--rounds N] [--time Nm] [--export FORMAT]

set -e

# Defaults
MAX_ROUNDS=10
TIME_LIMIT_SECONDS=300  # 5 minutes
TOPIC=""
EXPORT_FORMAT=""  # Export format(s): md, html, or both (comma-separated)

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
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            TOPIC="$1"
            shift
            ;;
    esac
done

if [[ -z "$TOPIC" ]]; then
    echo "Usage: $0 \"debate topic\" [--rounds N] [--time Nm] [--export FORMAT]"
    echo ""
    echo "Options:"
    echo "  --rounds N       Maximum number of rounds (default: 10)"
    echo "  --time Nm        Time limit in minutes (default: 5m)"
    echo "  --export FORMAT  Export transcript after debate ends"
    echo "                   FORMAT: md, html, or both (e.g., --export md,html)"
    echo ""
    echo "Example: $0 \"Should AI have emotions?\" --rounds 5 --time 3m --export md,html"
    exit 1
fi

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
TRANSCRIPT="$SCRIPT_DIR/transcript_${TIMESTAMP}.txt"
CONTROL="$SCRIPT_DIR/control.txt"

# Initialize files
echo "=== DEBATE: $TOPIC ===" > "$TRANSCRIPT"
echo "Started: $(date)" >> "$TRANSCRIPT"
ROUNDS_DESC=$([[ $MAX_ROUNDS -gt 0 ]] && echo "$MAX_ROUNDS rounds" || echo "no round limit")
TIME_DESC=$([[ $TIME_LIMIT_SECONDS -gt 0 ]] && echo "$((TIME_LIMIT_SECONDS / 60))m $((TIME_LIMIT_SECONDS % 60))s" || echo "no time limit")
echo "Limits: $ROUNDS_DESC, $TIME_DESC" >> "$TRANSCRIPT"
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
        pacing_hint="- FINAL TURNS: Work toward synthesis or provide a clear summary of your position"
    elif [[ $TIME_LIMIT_SECONDS -gt 0 ]] && [[ $remaining -lt 60 ]]; then
        pacing_hint="- TIME RUNNING LOW: Summarize your strongest points"
    fi

    local role_section=""
    if [[ -n "$opponent_arg" ]]; then
        role_section="You are $session. Argue AGAINST your opponent's position.

OPPONENT'S LAST ARGUMENT:
$opponent_arg

"
    else
        role_section="You are $session. Take a clear position on the topic and argue for it.

"
    fi

    cat <<EOF
DEBATE TOPIC: $TOPIC
STATUS: $status_line

${role_section}INSTRUCTIONS:
- Respond directly to your opponent's points (if any)
- Keep response focused (2-3 paragraphs)
- Be persuasive but fair
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

echo "Starting debate: $TOPIC"
echo "Limits: $ROUNDS_DESC, $TIME_DESC"
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
echo ">>> Judge evaluating the debate..."

DEBATE_CONTENT=$(cat "$TRANSCRIPT")
JUDGE_PROMPT=$(cat <<EOF
You are an impartial judge evaluating a debate.

DEBATE TOPIC: $TOPIC

FULL TRANSCRIPT:
$DEBATE_CONTENT

INSTRUCTIONS:
Analyze both sides' arguments and declare a winner. Your response should include:
1. **Summary**: Brief overview of each side's key arguments (2-3 sentences each)
2. **Strengths & Weaknesses**: What each side did well and where they fell short
3. **Winner**: State "Session A" or "Session B" as the winner
4. **Conclusion**: State the winning position as a clear, standalone statement (e.g., "Conclusion: Tabs are superior to spaces for indentation.")

Be fair and objective. Judge based on argument quality, not personal opinion on the topic.
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

echo ""
echo "Debate complete! Transcript saved to: $TRANSCRIPT"
echo "Total turns: $TURN"
