# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Align compact titlebar controls (Pi) | 验证中 | NeatEditorApp, WorkspaceSplitView, tab layout/item/strip, titlebar tests, TabStripGestures.md | 22:34 | 2026-10-26 22:41 | Native 40 pt row; unified 20 pt axis, layered topmost icon, 470 pt split containment and Settings minimum. Xcode 27.2 full tests/analyze/universal Release; logs build/titlebar-polish/logs. |
| Editor rendering repair (Pi) | 完成（待重启验收） | Editor/AppKitBridge container, gutter, ZoomableTextView; rendering tests; editing contract + parent KB | 15:02 | 2026-10-25 17:20 | TextKit 2 migration complete; no legacy layoutManager reads. Production-view fixture passed sequential insert/delete, 200-line bottom viewport, final-line and search-highlight captures; integrated initial surface checked. 91 tests + analyze + universal Release build pass. Pushed 94423bc/36ca51c; Release installed to /Applications, running 1.0.15 process intentionally not restarted for the tab owner's acceptance. |
