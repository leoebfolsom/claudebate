# Claude Code Debate System

Automated debates between two Claude Code sessions using file-based communication.

## Quick Start

```bash
./orchestrate.sh "Should AI systems have emotions?"
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--rounds N` | Maximum number of rounds (0 = unlimited) | 10 |
| `--time Nm` | Time limit in minutes (e.g., `5m`, `300s`) | 5m |

```bash
# Custom limits
./orchestrate.sh "Tabs vs spaces" --rounds 5 --time 3m

# Time limit only
./orchestrate.sh "Is OOP overrated?" --time 10m --rounds 0
```

## How It Works

1. The script invokes `claude -p` for each turn, alternating between PRO and CON positions
2. Each session receives the topic, their position, time/turn status, and opponent's last argument
3. Responses are appended to `transcript.txt`
4. Debate ends when round limit, time limit, or STOP signal is reached

## Stopping a Debate

**Graceful stop** (finishes current turn):
```bash
echo "STOP" > control.txt
```

**Immediate stop**: `Ctrl+C`

## Output Files

- `transcript_YYYY-MM-DD_HHMMSS.txt` - Full debate history (new file each run)
- `control.txt` - Write "STOP" here to end early
