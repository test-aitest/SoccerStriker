# Soccer Striker

A real-time, **agent-driven 4 vs 4 football game**. Both teams are played by autonomous AI
agents (powered by **Gemini 3.5 Flash**), and the human **steps in at decisive moments** by
swinging an iPhone as a motion controller — in the spirit of Nintendo Wii Sports.

The Mac runs the full 3D match; the iPhone is the controller.

> Built for the Gemini Tokyo Hackathon 2026.

```
┌──────────────────┐   Bonjour / UDP P2P    ┌─────────────────────────┐
│ SoccerStrikerKick │ ─────────────────────▶ │ SoccerStrikerMac         │
│ (iPhone controller)│  KickEvent             │ (game host)              │
│ CoreMotion 100Hz   │ ◀───────────────────── │ NetworkServer            │
│ → KickDetector     │  GoalEvent (haptics)   │ → GameModel (60Hz loop)  │
└──────────────────┘                         │ → SoccerEngine (4v4 AI)  │
         shared: SoccerShared                  │ → AgentBrain → Gemini    │
                                              │ → WebSceneKit (Three.js) │
                                              └─────────────────────────┘
```
## Demo
https://drive.google.com/file/d/1Rx09LLC_UcX4Fe_QHRBjXGOitECblelR/view?usp=sharing

## Concept

- **Agents play, humans join in.** You do not micromanage 8 players. The AI plays the match;
  you intervene only when it counts.
- **Attack — Shot chance:** when your team settles the ball near the goal, time freezes and a
  gauge appears. Nail it for a guaranteed goal.
- **Defense — Save chance:** when an on-target shot approaches your goal, a gauge appears.
  Nail it to save; miss and you concede.
- Two gauge types alternate: a **timing** gauge (swing inside the sweet zone) and a
  **power** gauge (mash within the time limit).

## How the AI works (the core idea)

An LLM cannot drive a 60fps game frame-by-frame — network latency and cost make per-frame
calls impossible. Soccer Striker uses a **hybrid agent loop**:

```
Gemini 3.5 Flash  ──(every ~1.5s)──▶  per-player intentions
   move / mark / pass / shoot / support / dribble  +  target position
                          │
                          ▼
60Hz local engine  ──▶  executes the intentions every frame (physics + steering)
```

- **Gemini is the decision-maker; the engine is the muscle.** The match never stalls waiting
  on the model, and players keep acting on their last intention between calls.
- If no API key is set or a call fails, the engine **gracefully falls back to a built-in
  rule-based AI** — the game always runs, fully offline.
- The rule-based layer is itself a real multi-agent system: possession model, player roles,
  steering with **separation** (no clustering), man-marking, pass-lane checks, off-ball runs.
- `SoccerEngine` is pure Swift and deterministic — covered by **16 unit tests**.

## Features

- 4 vs 4 (4 outfield + GK per side), both teams fully autonomous.
- National teams: Japan, Brazil, Spain, Argentina, Korea, USA — real flags (SVG) and
  per-nation kit colors; player models for Japan and Brazil.
- 3D pitch, players, goals and crowd rendered with **Three.js** inside a WebView; run
  animation, ball spin, uniforms by nation.
- **Cut-in animations**: shot, dribble, and a manager reaction ("tactics on point") when the
  agent's call pays off.
- **Audio**: procedural SFX (kick, whistle, chance cue) plus real stadium ambience and title
  BGM.
- iPhone haptics on goals and chances.
- UI in English for a global audience.

## Project layout

| Target / Package | Role |
|------------------|------|
| `SoccerShared` | Pure-Swift core: protocol, motion events, `KickDetector`, `SoccerEngine` (4v4 physics + multi-agent AI), `Intention`. Unit-tested. |
| `SoccerStrikerMac` | The game host. `NetworkServer`, `GameModel` (60Hz loop), `MatchView`, `AgentBrain` (Gemini client), `AudioFX`, country select. |
| `SoccerStrikerKick` | iPhone controller. `MotionStreamer`, `NetworkClient`, `HapticsPlayer`. |
| `Packages/WebSceneKit` | Generic WKWebView host for Three.js scenes. |
| `WebSource/pitch.js` | 3D pitch / players / ball rendering. |
| `slides/` | Pitch deck (`index.html`, `SoccerStriker.pdf`). |

## Tech stack

- **AI:** Gemini 3.5 Flash via the Gemini API (agentic, JSON-structured output)
- **App:** Swift 6 / SwiftUI — macOS game + iOS controller, shared Swift package
- **Render:** Three.js / WebKit
- **Motion & Net:** CoreMotion, Network.framework (Bonjour / UDP peer-to-peer)
- **Tooling:** XcodeGen, esbuild

## Setup

```bash
# 1. Build the web bundle (WebSource → Mac Resources/web)
npm install
npm run build            # or: npm run watch

# 2. Configure the Gemini API key (.env-style, read at build time)
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
#   then edit Config/Secrets.xcconfig:
#   GEMINI_API_KEY = AIza...        (get one from Google AI Studio)
#   Secrets.xcconfig is gitignored. Without a key the game runs on the rule-based AI.

# 3. Generate the Xcode project
xcodegen generate

# 4. Run
open SoccerStriker.xcodeproj     # run the SoccerStrikerMac scheme
```

Install `SoccerStrikerKick` on an iPhone and launch it; it auto-discovers the Mac on the same
Wi-Fi (or P2P / AWDL) and connects.

## Controls

- **iPhone:** when a gauge appears on a chance or pinch, **swing the device** (well-timed, or
  mash for the power gauge).
- **Keyboard (no iPhone needed):** `Space` = swing, `Esc` = back to title.

## Tests

```bash
cd SoccerShared && swift test      # 16 tests: engine, kick detection, protocol, AI behavior
```

Notable tests: ball advances into the opponent half, the AI generates chances over time, and
field players spread across the pitch width (no central clustering).

## Roadmap

1. 11 vs 11 and richer tactics driven directly by the agent.
2. glTF player models with real run / kick / dive motion.
3. Ball-follow camera, goal-net physics, replays.
4. Match flow: halves, clock, scoreboard polish, difficulty.
5. Online play and more national teams.
