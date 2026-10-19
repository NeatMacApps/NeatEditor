# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Code review and refactoring | 验证中 | Services/tests; editor bridge, workspace, command menus; release tooling, docs and version; excludes active title bar gesture files | 2026-10-01 21:12 | 2026-10-01 22:02 | Primary owns UI; services accepted, 39 tests and analyze passed; release worker running |
| Fix title bar double-click bounce | 验证中 | EditorTabItemView, TitleBarEventMonitor, gesture docs | 21:11 | 2026-10-01 22:05 | Duplicate zoom removed; full-tree Xcode build/test next; include in active release |
| Remove Text Softness from Settings (Codex primary) | 进行中 | SettingsView、workspace Settings minimum、obsolete localized strings、settings docs、1.0.9(9) build/release/install | 2026-10-19 15:58 | 2026-10-19 15:58 | User explicitly removes this Settings group. Existing older review rows are from 2026-10-01; no current Settings task. 51 tests plus fresh Debug build/analyze passed. Preparing universal Developer ID 1.0.9(9), then installed Settings capture; primary owns UI acceptance. |
