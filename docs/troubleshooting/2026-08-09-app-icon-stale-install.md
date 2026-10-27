# 应用图标更新后仍显示旧图标

改、替换或排查 NeatEditor 应用图标后，桌面、Finder 或系统搜索仍显示旧图标时使用本记录。用户说「图标被还原到几个月之前」「怎么又变成白底手写 A」时也读本篇。

## 一句话结论

构建成功并不代表正式安装版已携带新图标；必须同时确认构建产物与 `/Applications/NeatEditor.app` 内的图标一致，再清理旧注册记录并刷新系统图标服务。

**当前正式图标母版是蓝底、白纸卷在滚轴上，纸面印有深蓝色衬线 N 的那张，位于 `design/app-icon/AppIcon-1024.png`。** 工程图标资源必须跟母版走。白底手写 A 是 2026-03 占位图，不是现行图标；不得再留在资源集、本地构建产物或已登记的应用包里。从仍含占位图的旧提交拉仓或还原时，装包前先按母版换图标，禁止把占位图装回本机。

## Approved artwork (2026-10-27)

The owner approved the serif-N revision for production: the foreground roller hides the lower **one third of the complete letter height**, leaving the upper two thirds visible. This is intentional occlusion, not a nearly complete N merely touching the roller. Preserve the existing blue background, white sheet and folded corner, navy roller and cyan ends; do not recenter or resize the approved composition. The 1024 × 1024 master is opaque. Generate all ten existing macOS app-icon slots from that master and keep `docs/images/app-icon.png` synchronized for every localized README. Earlier blank-paper and nearly unoccluded-N candidates are not the current artwork.

Approved master SHA256: `8ff7b4e7b2b7e062e6eb4280c2a2a1c178f47ef296ae8221d409d7b50fc62cce`. Preserve these approved pixels rather than re-typesetting the letter with a locally available font. Artwork adoption does not prove that the installed or published app has changed; those targets still require the separate installation checks below.

### Adoption verification

Verified source `1ee450a` from an unchanged `git archive` snapshot on Xcode 27.2 (27B5028f), macOS 27.2 (26B118). Clean Debug and Release build/analyze compiled all 41 app Swift sources for both arm64 and x86_64; the native arm64 suite passed 112 tests / 142 parameter-expanded executions with no failures, skips or runtime warnings. No Swift compiler or analyzer issue was reported. The only retained diagnostic is the metadata-step notice `Metadata extraction skipped, no AppIntents.framework dependency found`, with its individual origin, residual limit and follow-up assessed in [code-review.md](../code-review.md#sidebar-review-2026-10-24).

All ten asset-catalog slots are opaque, correctly sized and derived from the approved master. Both compiled ICNS files decode to pixel-identical 32/128/256 px source derivatives; the compiled `Assets.car` contains all ten named renditions, including 1024 px. The legacy 16 px ICNS decoded by `iconutil` differs at its bottom-right pixel only: blue becomes 0 instead of 235, while red, green, alpha and the other 255 pixels match the approved PNG. This appears in both configurations; its compiler-versus-decoder origin is not isolated. The source PNG is unchanged. Residual risk is that single legacy corner pixel; reproduce with a stable toolchain and an independent decoder before attributing it to the artwork. Do not describe the 16 px ICNS as pixel-identical. The actual Release bundle's icon was inspected in Finder. The 48/24 px contrast gate passes (luminance spans 14.29:1 / 11.93:1; dominant-color contrast 5.54:1). Complete logs, structured results, source/environment fingerprints and the Finder capture remain under `build/icon-serif-n-20261027/committed-checks/`.

These are build-artifact checks, not installed or public-release acceptance. Intel and minimum-macOS runtime execution remain unverified. Final coordinated release installation must still perform the checks below; the icon-only change does not alter application source or version settings.

## 排查顺序

1. 确认图标母版和资源集中的各尺寸图片已经更新，且资源说明文件仍可解析。
2. 构建应用；构建日志必须显示图标资源已被编译，不能只看代码编译成功。
3. 分别从构建产物与 `/Applications/NeatEditor.app` 提取应用图标并做视觉比对。若正式安装版仍是旧图标，重新从当前构建产物完整覆盖安装，不能只替换应用内的单个资源文件。
4. 盘点 LaunchServices 记录，注销旧的安装备份和历史构建路径，压缩注册库后重新登记 `/Applications/NeatEditor.app`。
5. 刷新系统图标服务与 Finder，再从 `/Applications` 启动应用。

## 安装版本不能倒退

如果工程当前可构建的应用版本低于 `/Applications` 里正在使用的版本，**禁止为了更新图标而整包覆盖安装**。这会把用户已经在用的功能版本回退，哪怕图标变对也不算修复。

应当以原安装包为底：仅从已核对为正确的新构建中取出应用图标资源（传统 Mac 图标文件和资源目录中的图标目录），写入原安装包后用原有 Developer ID 重新签名；再完整覆盖回 `/Applications`、重新登记并启动。验收时同时确认：

- 正式安装版的版本号与更新前一致；
- 两份图标资源均来自已核对的新图，避免 Finder、Dock 和系统搜索各显示一套；
- 签名校验有效，且实际从 `/Applications` 启动成功。

## 只有 Dock 仍显示旧图

若正式安装版的两份图标资源都已更新、签名有效、Finder / 系统登记也已指向 `/Applications`，但正在运行的 Dock 图标仍是旧图，**不能直接归因为缓存，更不能宣布修复**。

先分别核对系统读取正式安装版得到的图标、Dock 固定入口所指向的应用路径，以及运行中应用是否临时指定了另一张 Dock 图。macOS 允许应用在运行期间临时指定 Dock 图；此时清缓存无效，应先消除这个覆盖。仅当上述三项都正确且实际画面仍旧时，才把当前用户的 `com.apple.dock.iconcache` 移入废纸篓、重启 Dock，让它重建缓存。该缓存可自动重建；不改 Dock 排列、不清除用户文件，也不要删除系统范围的图标缓存目录。

验收必须以 Dock 实际显示的新图为准，不能用“缓存已重建”或“应用已启动”替代。

## 验收标准

- 正式安装版提取出的应用图标与当前母版一致。
- LaunchServices 的主应用记录只保留 `/Applications/NeatEditor.app`。
- 应用从 `/Applications` 正常启动，Finder 中显示新图标。

## 禁止事项

- 不要仅凭构建成功、重新启动 Finder 或查看构建目录宣布图标已更新。
- 不要删除用户的安装备份来碰运气；先注销其系统注册记录，确认无回滚需要后再由维护者处理。

<!-- 该文档整理/压缩于 2026-09-05 -->
