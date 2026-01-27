# Claude Code Debate System

Automated debates between two Claude Code sessions using file-based communication.

## Quick Start

```bash
./debate.sh "What ice cream flavor really hits the spot?"

Starting debate: What ice cream flavor really hits the spot?
Limits: 10 rounds, 5m 0s
To stop early: echo 'STOP' > /Users/leoebfolsom/claude/claudebate/control.txt


>>> Session A - Turn 1...

**Session A's Position: Vanilla is the ice cream flavor that truly hits the spot.**

Vanilla is often dismissed as "plain" or "boring," but this reputation is profoundly unearned. In reality, vanilla is the most versatile, satisfying, and universally appealing ice cream flavor. Its subtle complexity—derived from actual vanilla bean with its hundreds of flavor compounds—provides a creamy, aromatic experience that complements virtually any dessert, topping, or mood. Whether paired with warm apple pie, drizzled with hot fudge, or enjoyed in a simple cone, vanilla delivers consistent satisfaction without overwhelming the palate.

Furthermore, vanilla's popularity speaks for itself: it consistently ranks as the best-selling ice cream flavor worldwide. This isn't because people lack imagination—it's because vanilla genuinely *works*. It's the foundation upon which countless desserts are built, from milkshakes to sundaes to ice cream sandwiches. While trendy flavors like salted caramel or matcha may capture momentary attention, vanilla endures because it satisfies a fundamental craving for comfort and balance. When you want ice cream that "really hits the spot," you want something reliable, delicious, and adaptable—and nothing fits that description better than a quality vanilla.


>>> Session B - Turn 2...

**Session B's Response: Vanilla's "Versatility" Is Actually Its Greatest Weakness**

My opponent argues that vanilla "works" because it's adaptable and complements other desserts—but this is precisely the problem. When we ask what flavor "really hits the spot," we're asking what delivers a satisfying, complete ice cream experience on its own terms. Vanilla's supposed strength is that it plays a supporting role: it needs the apple pie, the hot fudge, the cookie crumbles. Strip away the accompaniments, and vanilla reveals itself as a blank canvas rather than a masterpiece. If vanilla requires external enhancement to shine, can we honestly say it's the flavor that hits the spot—or is it merely the vehicle for other flavors that do?

Consider instead a flavor like **salted caramel** or **chocolate peanut butter**—flavors that deliver immediate, decisive satisfaction the moment they touch your tongue. These flavors don't need backup dancers. They arrive fully formed, with layers of sweetness, depth, and textural intrigue that command attention. The "hundreds of flavor compounds" in vanilla that my opponent mentions are so subtle that most commercial vanilla ice creams barely register them. Meanwhile, a well-crafted bold flavor provides an unmistakable sensory experience that lingers in memory.

As for vanilla's popularity being evidence of superiority—correlation isn't causation. Vanilla dominates sales because it's the safe, default choice, not because it's the most satisfying. It's the flavor you pick when you're sharing with a group and don't want to offend anyone. But "least objectionable" is not the same as "really hits the spot." When you truly want satisfaction, you reach for something with personality—something that makes a statement rather than fading politely into the background.


>>> Session A - Turn 3...
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
./debate.sh "Who is the greatest baseball player of all time?" --rounds 5 --time 3m

# No round limit (debate runs until time expires)
./debate.sh "Is OOP overrated?" --time 10m --rounds false

# No time limit (debate runs until rounds complete)
./debate.sh "Are we in an AI bubble?" --rounds 8 --time false
```

<img width="939" height="813" alt="Screenshot 2026-01-27 at 14 52 56" src="https://github.com/user-attachments/assets/58a36f7a-0857-47b3-9a76-5874e5f2b74a" />


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
