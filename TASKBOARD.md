# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Fix tab outline/title resize synchronization (Pi) | 验证中 | Tab local outline/scroll, geometry tests, TabStripGestures, integrated 1.0.15 release; Xcode 27.2 | 14:19 | 2026-10-25 14:29 | Debug 76 tests + analyze and universal Release build/analyze passed (build/resize-sync-logs). Snapshot/install then own motion acceptance; Pi is sole publisher. |
| macOS 26 baseline and API review | 验证中 | project/CI, toolbar pin, newline handling, docs; Xcode 27.2 + Sparkle | 14:20 | 2026-10-25 14:20 | 14:37 checks/preflight passed. Installing current committed final-gutter Debug for own fixture acceptance; publish only via existing script single-instance lock, no source edits planned. |
