#!/bin/bash

# Export existing debate transcripts to Markdown or HTML
# Usage: ./export.sh <transcript_file> --format md|html|both

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared export functions
source "$SCRIPT_DIR/export_functions.sh"

# Parse arguments
TRANSCRIPT_FILE=""
FORMAT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --format)
            FORMAT="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            exit 1
            ;;
        *)
            TRANSCRIPT_FILE="$1"
            shift
            ;;
    esac
done

# Show usage if missing arguments
if [[ -z "$TRANSCRIPT_FILE" ]] || [[ -z "$FORMAT" ]]; then
    echo "Usage: $0 <transcript_file> --format md|html|both"
    echo ""
    echo "Export existing debate transcripts to Markdown or HTML format."
    echo ""
    echo "Arguments:"
    echo "  transcript_file    Path to the transcript .txt file"
    echo "  --format FORMAT    Export format: md, html, or both"
    echo ""
    echo "Examples:"
    echo "  $0 transcript_2024-01-01_120000.txt --format md"
    echo "  $0 ./transcripts/debate.txt --format html"
    echo "  $0 transcript.txt --format both"
    exit 1
fi

# Validate transcript file exists
if [[ ! -f "$TRANSCRIPT_FILE" ]]; then
    echo "Error: File not found: $TRANSCRIPT_FILE"
    exit 1
fi

# Validate transcript file is a debate transcript
if ! grep -q "^=== DEBATE:" "$TRANSCRIPT_FILE"; then
    echo "Error: File does not appear to be a valid debate transcript: $TRANSCRIPT_FILE"
    echo "Expected to find '=== DEBATE:' header line."
    exit 1
fi

# Validate format argument
case "$FORMAT" in
    md|html|both)
        ;;
    *)
        echo "Error: Invalid format '$FORMAT'. Must be: md, html, or both"
        exit 1
        ;;
esac

# Convert to absolute path if relative
if [[ "$TRANSCRIPT_FILE" != /* ]]; then
    TRANSCRIPT_FILE="$(pwd)/$TRANSCRIPT_FILE"
fi

# Export based on format
if [[ "$FORMAT" == "md" || "$FORMAT" == "both" ]]; then
    md_file=$(export_to_md "$TRANSCRIPT_FILE")
    echo "Exported to Markdown: $md_file"
fi

if [[ "$FORMAT" == "html" || "$FORMAT" == "both" ]]; then
    html_file=$(export_to_html "$TRANSCRIPT_FILE")
    echo "Exported to HTML: $html_file"
fi

echo ""
echo "Export complete!"
