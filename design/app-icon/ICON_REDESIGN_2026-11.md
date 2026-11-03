# App icon redesign (started 2026-11-03)

Status: **adopted 2026-11-03** ("定稿D01"). Production master `design/app-icon/AppIcon-1024.png` is
`explorations/variants-2026-11-03-D/raw/D1.png`: jade-green translucent glass portable typewriter, typebar fan visible
through the glass, five frosted ivory keys, charcoal roller, white sheet with four typed dots and a cursor block, on
near-black with a soft jade glow. The previous master (blue roller with serif N) is archived as
`explorations/AppIcon-before-typewriter.png`.

Constraints: keep the model's rendering and composition; do not re-centre, flatten, recolour or re-glass it. The `.icon`
wraps the whole master as one layer with glass, shadow, specular and translucency off. The iOS app uses the same master.

## Brief

- Product job: a minimal, fast plain-text editor that keeps the interface quiet so attention stays on the text.
- Name picture: "Neat" + writing plain text. Avoid symbols already owned in the category
  (iA Writer caret, Day One bookmark, Ulysses butterfly, pen nibs, Obsidian paperclip) and the owner's
  other products (Write Down yellow pencil, NeatPaste keycaps, TextSnap glass quotation marks).
- Market strip: `explorations/market-2026-11-03/strip.png` (16 current App Store writing apps, calibration only).

## Rounds and owner reactions

- **A board** (`explorations/directions-2026-11-03-A/`): shown A1 folded ruled-paper N on library green,
  A2 vintage typewriter key N on black, A3 (`raw/A3b.png`) flat jade-green portable typewriter with one row of
  five ivory keys and a sheet with a short typed line and cursor block, on white. Withheld by agent screening:
  a puffy toy-like mint typewriter (weak separation on white) and a binder-clipped paper stack on yellow
  (read as Apple Notes).
  Owner reaction 2026-11-03: picked **A3 typewriter** and asked for variants ("打字机 给我出几个变种").
- **V board** (`explorations/variants-2026-11-03-V/`, `board.png`): nine one-axis variants of A3b with a shared fix
  (crisp sheet edge for separation): V1 closer crop with the sheet off the top edge, V2 black ground, V3 deep jade ground,
  V4 tomato-red body on warm white, V5 sky-cobalt body on cream, V6 sheet types a serif N, V7 (`raw/V7b.png`) cut paper,
  V8 translucent jade glass, V9 three-quarter view. Withheld: first V7 (near-duplicate of A3b).
  Owner reaction 2026-11-03: liked **V8 translucent glass** ("半透明玻璃不错") and asked for further variants, mainly of the
  typewriter's form ("主要是打字机样式").
- **W board** (`explorations/variants-2026-11-03-W/`): variants of V8 that keep the glass rendering and change the typewriter's form:
  W1 1950s rounded portable, W2 1920s desktop with three key rows, W4 carriage-return lever and paper bail, W5 typebar fan
  visible through the glass, W6 two staggered key rows, W7 sheet curling back at the top, W8 black ground, W9 closer crop.
  Withheld: W3 thin wedge with square keys (read as a receipt printer).
  Owner reaction 2026-11-03: picked **W5** (Finder preview `NeatEditor W 04.app`, typebar fan visible through the glass)
  and asked for colour variants ("04出不同配色变体"). Lesson: label handoff images with the same numbers as the
  Finder preview apps; the gap left by a withheld cell made the two numberings disagree.
- **C board** (`explorations/variants-2026-11-03-C/`): colour-only variants of W5, numbered to match the Finder previews:
  C1 jade on black, C2 smoky clear glass on white, C3 amber on cream, C4 sapphire on icy white, C5 ruby on warm white,
  C6 milk-white glass on sky blue, C7 obsidian smoked glass on warm white. Withheld: aquamarine on deep teal
  (`withheld/C6-greyed-teal-ground.png`, greyed teal field).
  Owner reaction 2026-11-03: none of the recolours; back to the **jade-green W5** ("算了 还是绿色打字机好看"),
  asked for ground-colour variants.
- **G board** (`explorations/variants-2026-11-03-G/`): W5 unchanged on new grounds; W5 (white) and C1 (black) shown as references.
  G1 ivory cream, G2 pale mint, G3 deep forest green, G4 soft graphite, G5 light aluminium grey, G6 blush rose
  (numbers match the Finder previews). Owner reaction 2026-11-03: asked for more dark grounds ("出几个深色背景的变种").
- **D board** (`explorations/variants-2026-11-03-D/`): W5 unchanged on new dark grounds; C1 black, G3 forest, G4 graphite as references.
  D1 near-black with a jade glow, D2 midnight blue, D3 oxblood, D4 deep petrol (numbers match the Finder previews).
  Withheld: dark slate (`withheld/D3-slate-near-duplicate-of-G4.png`). Owner reaction 2026-11-03: adopted **D1**
  unchanged ("定稿D01") and asked to publish a new release ("然后发布新版").

- **Legibility review** (after the 1.0.26 release): owner: "我发现看上去对比度辨识度有点问题". Measured on D1: the
  charcoal roller is 1.85:1 against the ground and vanishes, so at Dock sizes the mark reads as a white sheet over a
  green tray; the paper (17:1) outweighs the jade body (5.1:1); the glow (1.31:1) disappears below 64 px. The automated
  gate passed only because it measures the paper-to-black extreme. Lesson: also check that the feature which names the
  object survives at 32 px, not just global contrast. Owner delegated the fix ("你自己看着办重新生成").
- **R round** (`explorations/refine-2026-11-03-R/`, `compare@2x.png`): single-issue edits of D1. R1 satin-silver roller
  and knobs (roller 11.8:1, body 12.2:1, gate passes); R2 = R1 + ivory paper one third shorter (balanced, but the gate's
  dominant-pair metric fails at 48/24 px because the graded paper no longer forms a 4 % colour cluster); R2b neutral
  grey-white paper (dull, also fails at 24 px); R3 = R2 + jade-black ground (icon edge against a dark Dock only 1.18 to
  1.24, so it does not solve that). Recommended R1. Owner reaction: pending.

## Shipping (2026-11-03)

- macOS: [v1.0.26](https://github.com/NeatMacApps/NeatEditor/releases/tag/v1.0.26) from source `ca678cb`, appcast commit
  `ba3131d`, built in a fresh clone because this checkout held another session's uncommitted docs (R1). Apple accepted
  app submission `0b560684-2c9e-4442-b453-6691419d2bcc` and DMG submission `5418f3c1-6e9e-4997-9883-50775b8c6b8c`.
  Anonymous downloads matched SHA256SUMS and the local notarized files: DMG
  `deb33eb695512cfeeaa65ab8710e0af950b47dc07a18ce71ae16d52ad9fc3d50`, ZIP
  `a3275d169d7536f8eb5db5737f8951fb250206ce21e52f745483aa5b012d251d`; the raw appcast serves build 26 with the ZIP's length.
  The publisher stopped before its appcast commit because the global `sync-agent-files` pre-commit hook tried to
  `git add` the gitignored `CLAUDE.md` it creates in a fresh clone; the appcast-only commit was retried and pushed
  (hook fixed: `~/.config/agentsync/docs/WORKSPACE_ORGANIZATION_GUIDE.md`).
  Gate before release: 149 tests in 19 suites, universal Release build, Debug analyze; the only diagnostic was the
  retained AppIntents metadata notice. Installed from the public DMG (same Developer ID, strict signature and stapled
  ticket pass, `spctl`: `source=Notarized Developer ID`, `override=security disabled`), executable SHA256
  `ce8cf9a4e22f1174a4cd97b7c98958c9a6c23624abf5f742016b5bd6f23b3610`; Finder shows the typewriter icon and the app
  restored its tabs. The session was locked, so the Dock was not captured. The 1.0.26 entry belongs in `RELEASING.md`,
  which currently holds another session's staged edits; add it there once that work is committed.
- iOS: build 5 (`neateditor-ios` `01357eb`) passed 10 simulator tests, was signed and uploaded to AppShelf
  (release 425, https://apps.caozc.com/a/neateditor). Direct installation failed with `device_unavailable` (phone away);
  home-screen acceptance on the phone remains open.
