# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Code review and refactoring | 进行中 | Services and service tests; editor bridge and workspace store review; release tooling and README; excludes active pin files | 2026-10-01 21:12 | 2026-10-01 21:12 | Primary owns all UI; OpenCode owns isolated services/release tooling; Xcode required |
| Fix title bar double-click bounce | 进行中 | EditorTabItemView, TitleBarEventMonitor only, gesture docs, release | 21:11 | 2026-10-01 21:11 | Later task yields on EditorTabStripView while pin task edits; no pin-area changes; gesture docs already recorded |
