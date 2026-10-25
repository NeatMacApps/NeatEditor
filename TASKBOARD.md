# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Editor rendering repair (Pi) | 进行中 | Editor/AppKitBridge container, gutter, ZoomableTextView; rendering tests; editing contract + parent KB | 15:02 | 2026-10-25 15:14 | Native A/B reproduced TK1 ghost pixels, equal buffers/TK2 clean. Migrating all legacy consumers with macOS 26 public APIs; separate build/editor-render-validation. No target restart until coordinated with tab owner; include editor in final integrated release. |
| Rewrite document-tab component (Pi) | 验证中 | Native tab strip/item/layout/top rule; WorkspaceSplitView/WorkspaceView; tests/docs; integrated 1.0.15 release | 14:19 | 2026-10-25 15:16 | Primary resuming full acceptance and sole publication. Fixed title measurement using actual configured cell; owns tests/motion/install/release. Other reviews please stop verification runs/source edits; preserve your artifacts. No concurrent target restarts. |
