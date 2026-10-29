# 2026-10-29 启动分段采样与保存/加载阈值排坑记录

## 启动 6 段（M1 Pro，单实例直接跑二进制，Debug 与 -O+DEBUG 段形态一致，main→task 约 280–320ms）

| 段 | 实测 | 归属 |
|---|---|---|
| main→store | ~6–11ms | 自有（WorkspaceStore 初始化 + 进程级首次调用） |
| store→body | ~50–75ms | 框架（Scene/Window/菜单命令） |
| body→make | ~90–105ms | 框架（SwiftUI 首遍 view graph → 桥接） |
| make→bridge | ~4ms | 自有（split init：2×NSHostingController + strip，已精益） |
| bridge→editor | ~18–35ms | 自有（编辑器栈 + 字体） |
| editor→frame | ~92–99ms | 框架 + 必需可见工作（首布局 + List + 绘制） |

自有约 45ms，框架约 245ms（83%）。 further 压缩意味着推迟可见内容，得不偿失，停止。

## 已落决策

- Sparkle（`AppUpdater`）改懒启动，首帧 `.task` 里 `warmUp()`；A/B 5 次 mainToStore 中位数省约 4ms（9.6 vs 13.9ms）。代价：启动后约 300ms 内“检查更新”菜单短暂不可用。
- 读按 2MB 分支：`<2MB` 用 `String(contentsOf:)`（快 30–40%），大文件用 `mappedIfSafe`（10MB 快约 46%）。`loadTabContentIfNeeded` 与 `openDocument` 同阈值。
- `tabs.map` 不缓存：`EditorTabStripView.update` 已有 `Equatable` 早退且 descriptor 不含正文，每击键约 1µs。
- `queueAutoSave` 走后台入口；`saveDocument`/`saveAllDocuments`/切换/关闭/退出路径保持同步语义（fire-and-forget 版坏过 3 个同步契约测试，已回退）。

## 采样排坑（可复用）

1. `timeout N xctrace ... --launch` 超时只杀 xctrace，不杀被测子进程：残留进程会污染后续 `pgrep|head -1` 与窗口轮询。测前必须 `kill -9` 并确认 `pgrep` 为空。
2. 签名应用忽略 `DYLD_PRINT_STATISTICS`；改用进程内 `CFAbsoluteTime` checkpoint（一行 log + DEBUG 文件落点，见 `Sources/NeatEditor/App/LaunchProfiler.swift`，用法：`cat /tmp/neat-launch-times.log`）。
3. 锁屏会话截屏全黑、窗口轮询不可靠；此时以进程内 profiler 为准，不以像素为准。
4. Debug 产物是 stub（`__preview.dylib` JIT 链接）+ `NeatEditor.debug.dylib`，Release 是 universal 单文件；两者 in-app 段形态一致，但端到端数字不可混比。
5. `open` 对已运行实例只做激活：采样前确认单实例，否则量到的是激活时间。

共享提升待定：以上方法论暂无对应共享权威（MACOS 系列指南均未覆盖冷启动分段方法），先记产品本地；候选 `MAC_PERFORMANCE_GOVERNANCE_GUIDE.md` 变体待下次治理时评估。
