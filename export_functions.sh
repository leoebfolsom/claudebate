#!/bin/bash

# Shared export functions for claudebate
# These functions can be sourced by debate.sh and export.sh

# Convert markdown code blocks to HTML pre/code tags
# Uses AWK state machine to track in_code_block state
# Usage: echo "$content" | convert_code_blocks
convert_code_blocks() {
    awk '
        BEGIN {
            in_code_block = 0
            code_lang = ""
        }
        /^```/ {
            if (in_code_block == 0) {
                # Opening code block - extract language if present
                in_code_block = 1
                code_lang = $0
                gsub(/^```/, "", code_lang)
                gsub(/[[:space:]].*$/, "", code_lang)  # Remove anything after language
                if (code_lang != "") {
                    print "<pre><code class=\"language-" code_lang "\">"
                } else {
                    print "<pre><code>"
                }
                next
            } else {
                # Closing code block
                in_code_block = 0
                code_lang = ""
                print "</code></pre>"
                next
            }
        }
        {
            if (in_code_block) {
                # HTML-escape content inside code blocks
                gsub(/&/, "\\&amp;")
                gsub(/</, "\\&lt;")
                gsub(/>/, "\\&gt;")
            }
            print
        }
        END {
            # Handle unclosed code blocks gracefully
            if (in_code_block) {
                print "</code></pre>"
            }
        }
    '
}

# Convert markdown headers to HTML h1-h6 tags
# Uses sed -E for extended regex (macOS compatible)
# Process from longest pattern to shortest to avoid partial matches
# Usage: echo "$content" | convert_headers
convert_headers() {
    sed -E \
        -e 's/^###### (.*)$/<h6>\1<\/h6>/' \
        -e 's/^##### (.*)$/<h5>\1<\/h5>/' \
        -e 's/^#### (.*)$/<h4>\1<\/h4>/' \
        -e 's/^### (.*)$/<h3>\1<\/h3>/' \
        -e 's/^## (.*)$/<h2>\1<\/h2>/' \
        -e 's/^# (.*)$/<h1>\1<\/h1>/'
}

# Convert markdown bold/italic to HTML strong/em tags
# Skips lines that are already HTML tags (pre, code, h1-h6)
# HTML-escapes non-tag lines before converting
# Usage: echo "$content" | convert_inline_formatting
convert_inline_formatting() {
    awk '
        {
            # Skip lines that are already HTML tags (pre, code, h1-h6)
            if (/^<pre>/ || /^<\/pre>/ || /^<code/ || /^<\/code>/ || /^<h[1-6]>/ || /^<\/h[1-6]>/) {
                print
                next
            }

            # Also skip content inside code blocks (already escaped by convert_code_blocks)
            if (/^<pre><code/) {
                print
                next
            }

            line = $0

            # HTML-escape non-tag lines (& first, then < and >)
            gsub(/&/, "\\&amp;", line)
            gsub(/</, "\\&lt;", line)
            gsub(/>/, "\\&gt;", line)

            # Convert **text** to <strong>text</strong> (process before single *)
            while (match(line, /\*\*[^*]+\*\*/)) {
                before = substr(line, 1, RSTART - 1)
                matched = substr(line, RSTART + 2, RLENGTH - 4)
                after = substr(line, RSTART + RLENGTH)
                line = before "<strong>" matched "</strong>" after
            }

            # Convert __text__ to <strong>text</strong>
            while (match(line, /__[^_]+__/)) {
                before = substr(line, 1, RSTART - 1)
                matched = substr(line, RSTART + 2, RLENGTH - 4)
                after = substr(line, RSTART + RLENGTH)
                line = before "<strong>" matched "</strong>" after
            }

            # Convert *text* to <em>text</em> (avoid matching ** which is already converted)
            while (match(line, /\*[^*]+\*/)) {
                before = substr(line, 1, RSTART - 1)
                matched = substr(line, RSTART + 1, RLENGTH - 2)
                after = substr(line, RSTART + RLENGTH)
                line = before "<em>" matched "</em>" after
            }

            # Convert _text_ to <em>text</em> (avoid matching __ which is already converted)
            while (match(line, /_[^_]+_/)) {
                before = substr(line, 1, RSTART - 1)
                matched = substr(line, RSTART + 1, RLENGTH - 2)
                after = substr(line, RSTART + RLENGTH)
                line = before "<em>" matched "</em>" after
            }

            print line
        }
    '
}

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
        /* Code block styling */
        pre {
            background-color: #2c3e50;
            border-radius: 8px;
            padding: 15px;
            overflow-x: auto;
            margin: 15px 0;
        }
        pre code {
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Fira Code', monospace;
            font-size: 0.9em;
            color: #ecf0f1;
            line-height: 1.4;
        }
        code {
            font-family: 'SF Mono', 'Monaco', 'Inconsolata', 'Fira Code', monospace;
            background-color: #ecf0f1;
            padding: 2px 6px;
            border-radius: 4px;
            font-size: 0.9em;
            color: #c0392b;
        }
        pre code {
            background-color: transparent;
            padding: 0;
            color: #ecf0f1;
        }
        /* Header styling */
        h2 {
            color: #2c3e50;
            border-bottom: 2px solid #bdc3c7;
            padding-bottom: 8px;
            margin-top: 25px;
            margin-bottom: 15px;
        }
        h3 {
            color: #34495e;
            margin-top: 20px;
            margin-bottom: 12px;
        }
        h4 {
            color: #34495e;
            margin-top: 18px;
            margin-bottom: 10px;
        }
        h5 {
            color: #7f8c8d;
            margin-top: 15px;
            margin-bottom: 8px;
        }
        h6 {
            color: #95a5a6;
            margin-top: 12px;
            margin-bottom: 6px;
            font-size: 0.95em;
        }
        /* Inline formatting */
        strong {
            color: #2c3e50;
        }
        em {
            color: #34495e;
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
