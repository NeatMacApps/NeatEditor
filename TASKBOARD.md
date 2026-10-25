# TASKBOARD — 多 Agent 并行协作看板

> 规则见 agentsync 全局 docs/AGENT_TASKBOARD_GUIDE.md。只编辑自己的条目；完成后删除。

| 任务 | 状态 | 影响范围 | 开始 | 最近更新 | 备注 |
|---|---|---|---|---|---|
| Rewrite document-tab component (Pi) | 进行中 | Native tab strip/item/layout/top rule; WorkspaceSplitView/WorkspaceView; tests/docs; integrated 1.0.15 release | 14:19 | 2026-10-25 14:40 | Owner authorized rewrite. Prior patch failed dynamic rule-gap acceptance. Pi owns UI and sole publication; no install/restart of target during motion acceptance. |
| macOS 26 baseline and API review | 验证中 | project/CI, toolbar pin, newline handling, docs; Xcode 27.2 + Sparkle | 14:20 | 2026-10-25 14:20 | 14:53 baseline checks/fixture done; pin API preserved. New install raced fixture-close readback (fixture still visible), so no further UI during Pi acceptance. I will inspect final diagnostics/release, then close only named test fixture. |
