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

# Export functions
export_to_md() {
    local transcript_path="$1"
    local md_path="${transcript_path%.txt}.md"

    # Read the transcript
    local content
    content=$(cat "$transcript_path")

    # Extract metadata from the header
    local topic
    topic=$(echo "$content" | grep -m1 "^=== DEBATE:" | sed 's/=== DEBATE: //;s/ ===//')

    local started
    started=$(echo "$content" | grep -m1 "^Started:" | sed 's/Started: //')

    local limits
    limits=$(echo "$content" | grep -m1 "^Limits:" | sed 's/Limits: //')

    # Count total turns by counting "--- Session" lines
    local total_turns
    total_turns=$(echo "$content" | grep -c "^--- Session")

    # Start writing the markdown file
    {
        echo "# $topic"
        echo ""
        echo "**Date:** $started"
        echo ""
        echo "**Limits:** $limits"
        echo ""
        echo "**Total Turns:** $total_turns"
        echo ""
        echo "---"
        echo ""

        # Process the transcript content
        # We'll use awk to handle the different sections
        echo "$content" | awk '
            /^--- Session/ {
                # Extract session and turn info
                gsub(/^--- /, "")
                gsub(/ ---$/, "")
                print "## " $0
                print ""
                next
            }
            /^=== JUDGE'\''S VERDICT ===/ {
                print "## Judge'\''s Verdict"
                print ""
                next
            }
            /^=== DEBATE:/ || /^Started:/ || /^Limits:/ || /^=+$/ {
                # Skip header lines we already processed
                next
            }
            /^=== DEBATE ENDED/ {
                # Skip the ended line
                next
            }
            {
                # Print regular content as blockquotes (if not empty)
                if (NF > 0) {
                    print "> " $0
                } else {
                    print ""
                }
            }
        '
    } > "$md_path"

    echo "$md_path"
}

export_to_html() {
    local transcript_path="$1"
    local html_path="${transcript_path%.txt}.html"

    # Read the transcript
    local content
    content=$(cat "$transcript_path")

    # Extract metadata from the header
    local topic
    topic=$(echo "$content" | grep -m1 "^=== DEBATE:" | sed 's/=== DEBATE: //;s/ ===//')

    local started
    started=$(echo "$content" | grep -m1 "^Started:" | sed 's/Started: //')

    local limits
    limits=$(echo "$content" | grep -m1 "^Limits:" | sed 's/Limits: //')

    # Count total turns by counting "--- Session" lines
    local total_turns
    total_turns=$(echo "$content" | grep -c "^--- Session")

    # Start writing the HTML file
    {
        cat <<'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Debate Transcript</title>
    <style>
        * {
            box-sizing: border-box;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
            line-height: 1.6;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
            color: #333;
        }
        h1 {
            color: #2c3e50;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        .metadata {
            background-color: #ecf0f1;
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
        }
        .metadata p {
            margin: 5px 0;
        }
        .session-a {
            background-color: #e8f4f8;
            border-left: 4px solid #3498db;
            padding: 15px;
            margin: 15px 0;
            border-radius: 0 8px 8px 0;
        }
        .session-b {
            background-color: #fdf2e9;
            border-left: 4px solid #e67e22;
            padding: 15px;
            margin: 15px 0;
            border-radius: 0 8px 8px 0;
        }
        .session-header {
            font-weight: bold;
            font-size: 1.1em;
            margin-bottom: 10px;
            color: #2c3e50;
        }
        .session-a .session-header {
            color: #2980b9;
        }
        .session-b .session-header {
            color: #d35400;
        }
        .verdict {
            background-color: #e8f8f5;
            border: 2px solid #27ae60;
            padding: 20px;
            margin: 25px 0;
            border-radius: 8px;
        }
        .verdict h2 {
            color: #27ae60;
            margin-top: 0;
            border-bottom: 2px solid #27ae60;
            padding-bottom: 10px;
        }
        .content p {
            margin: 10px 0;
        }
        .ended-note {
            text-align: center;
            color: #7f8c8d;
            font-style: italic;
            margin: 20px 0;
        }
    </style>
</head>
<body>
HTMLHEAD

        # Write the title and metadata
        echo "    <h1>$topic</h1>"
        echo "    <div class=\"metadata\">"
        echo "        <p><strong>Date:</strong> $started</p>"
        echo "        <p><strong>Limits:</strong> $limits</p>"
        echo "        <p><strong>Total Turns:</strong> $total_turns</p>"
        echo "    </div>"

        # Process the transcript content with awk
        echo "$content" | awk '
            BEGIN {
                in_section = 0
                section_type = ""
                in_verdict = 0
            }
            /^--- Session A/ {
                if (in_section) {
                    print "    </div>"
                    print "    </div>"
                }
                in_section = 1
                section_type = "a"
                # Extract the header text
                header = $0
                gsub(/^--- /, "", header)
                gsub(/ ---$/, "", header)
                print "    <div class=\"session-a\">"
                print "        <div class=\"session-header\">" header "</div>"
                print "        <div class=\"content\">"
                next
            }
            /^--- Session B/ {
                if (in_section) {
                    print "    </div>"
                    print "    </div>"
                }
                in_section = 1
                section_type = "b"
                # Extract the header text
                header = $0
                gsub(/^--- /, "", header)
                gsub(/ ---$/, "", header)
                print "    <div class=\"session-b\">"
                print "        <div class=\"session-header\">" header "</div>"
                print "        <div class=\"content\">"
                next
            }
            /^=== JUDGE'\''S VERDICT ===/ {
                if (in_section) {
                    print "    </div>"
                    print "    </div>"
                }
                in_section = 0
                in_verdict = 1
                print "    <div class=\"verdict\">"
                print "        <h2>Judge'\''s Verdict</h2>"
                print "        <div class=\"content\">"
                next
            }
            /^=== DEBATE:/ || /^Started:/ || /^Limits:/ || /^=+$/ {
                # Skip header lines we already processed
                next
            }
            /^=== DEBATE ENDED/ {
                if (in_section) {
                    print "    </div>"
                    print "    </div>"
                    in_section = 0
                }
                # Extract the reason
                reason = $0
                gsub(/^=== DEBATE ENDED \(/, "", reason)
                gsub(/\) ===$/, "", reason)
                print "    <p class=\"ended-note\">Debate ended: " reason "</p>"
                next
            }
            {
                # Print regular content as paragraphs (if not empty)
                if (NF > 0) {
                    # Escape HTML special characters
                    gsub(/&/, "\\&amp;", $0)
                    gsub(/</, "\\&lt;", $0)
                    gsub(/>/, "\\&gt;", $0)
                    print "            <p>" $0 "</p>"
                }
            }
            END {
                if (in_section || in_verdict) {
                    print "        </div>"
                    print "    </div>"
                }
            }
        '

        echo "</body>"
        echo "</html>"
    } > "$html_path"

    echo "$html_path"
}

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
echo "Debate complete! Transcript saved to: $TRANSCRIPT"
echo "Total turns: $TURN"
