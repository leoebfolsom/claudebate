# Claude Code Debate System

Automated debates between two Claude Code sessions using file-based communication.

## Quick Start

```bash
./debate.sh "Should AI systems have emotions?"
```

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--rounds N` | Maximum number of rounds | 10 |
| `--rounds false` | No round limit | |
| `--time Nm` | Time limit (e.g., `5m`, `300s`) | 5m |
| `--time false` | No time limit | |

```bash
# Custom limits
./debate.sh "Tabs vs spaces" --rounds 5 --time 3m

# No round limit (debate runs until time expires)
./debate.sh "Is OOP overrated?" --time 10m --rounds false

# No time limit (debate runs until rounds complete)
./debate.sh "Vim vs Emacs" --rounds 8 --time false
```

## How It Works

1. The script invokes `claude -p` for each turn, alternating between PRO and CON positions
2. Each session receives the topic, their position, time/turn status, and opponent's last argument
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
- `control.txt` - Write "STOP" here to end early
