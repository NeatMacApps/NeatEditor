# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Native full-height sidebar and code review | 进行中 | Workspace sidebar, split layout/titlebar integration, sidebar persistence and tests, docs/release; Xcode 27.2 | 10-24 14:35 | 2026-10-24 16:56 | Owner requires original rounded stepped tabs, rejects segmented replacement; preserve one row, stable sort and collapse fix; verify installed screenshots |
| Code review and refactoring | 验证中 | Services/tests; editor bridge, workspace, command menus; release tooling, docs and version; excludes active title bar gesture files | 2026-10-01 21:12 | 2026-10-01 22:02 | Primary owns UI; services accepted, 39 tests and analyze passed; release worker running |
| Fix title bar double-click bounce | 验证中 | EditorTabItemView, TitleBarEventMonitor, gesture docs | 21:11 | 2026-10-01 22:05 | Duplicate zoom removed; full-tree Xcode build/test next; include in active release |
