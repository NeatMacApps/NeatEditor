# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Floating character count (Pi) | 验证中 | WorkspaceView overlay; EditorTextView character reporting; EditorCharacterCount model/worker + tests; editor bottom inset; editing contract | 23:04 | 2026-10-26 23:36 | Owner simplified the footer: only a non-interactive character count floating at the document editor's bottom-right; no full-width row, no gutter use, no lines/position/font/popover. Reserve bottom scroll inset so the last line stays above it. Own build/character-count paths. |
| Editor rendering repair (Pi) | 完成（待重启验收） | Editor/AppKitBridge container, gutter, ZoomableTextView; rendering tests; editing contract + parent KB | 15:02 | 2026-10-25 17:20 | TextKit 2 migration complete; no legacy layoutManager reads. Production-view fixture passed sequential insert/delete, 200-line bottom viewport, final-line and search-highlight captures; integrated initial surface checked. 91 tests + analyze + universal Release build pass. Pushed 94423bc/36ca51c; Release installed to /Applications, running 1.0.15 process intentionally not restarted for the tab owner's acceptance. |
