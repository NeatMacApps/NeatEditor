# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Adopt serif N app icon (Pi) | 进行中 | design/app-icon, AppIcon.appiconset, docs/images/app-icon.png, icon troubleshooting doc; isolated icon build/install | 10-27 10:10 | 2026-10-27 10:10 | Owner approved the serif N with its lower third hidden behind the roller. Preserve version 1.0.17; no public release or source/config changes. |
| Persistence refactor and 1.0.17 release (Pi) | 进行中 | Services/DocumentPersistenceService*, persistence/sidebar tests, release config and docs | 10-27 10:01 | 2026-10-27 10:01 | Preserve existing UI and file rules; Xcode/XcodeGen, universal Debug/Release checks and local signed publisher. |
| Editor rendering repair (Pi) | 完成（待重启验收） | Editor/AppKitBridge container, gutter, ZoomableTextView; rendering tests; editing contract + parent KB | 15:02 | 2026-10-25 17:20 | TextKit 2 migration complete; no legacy layoutManager reads. Production-view fixture passed sequential insert/delete, 200-line bottom viewport, final-line and search-highlight captures; integrated initial surface checked. 91 tests + analyze + universal Release build pass. Pushed 94423bc/36ca51c; Release installed to /Applications, running 1.0.15 process intentionally not restarted for the tab owner's acceptance. |
