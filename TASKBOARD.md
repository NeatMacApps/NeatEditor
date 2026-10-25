# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Editor rendering research (Pi) | 进行中 | docs/editing-text-sync-test-cases.md; parent docs/EDITOR_SYNC_KNOWLEDGE_BASE.md; ignored native API probe | 15:02 | 2026-10-25 15:02 | Research/docs only; no production source, code-review.md, target restart, installation or release changes. |
| Rewrite document-tab component (Pi) | 验证中 | Native tab strip/item/layout/top rule; WorkspaceSplitView/WorkspaceView; tests/docs; integrated 1.0.15 release | 14:19 | 2026-10-25 15:16 | Primary resuming full acceptance and sole publication. Fixed title measurement using actual configured cell; owns tests/motion/install/release. Other reviews please stop verification runs/source edits; preserve your artifacts. No concurrent target restarts. |
| macOS 26 baseline and API review | 验证中 | project/CI, toolbar pin, newline handling, docs; Xcode 27.2 + Sparkle | 14:20 | 2026-10-25 14:20 | 15:12 signing retry passed; actor warnings fixed. 84 tests now run, title sizing still fails two cases by ~4pt. Investigating actual native cell metrics; no target restart; preserving existing tab design/interaction. |
