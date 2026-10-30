# macOS 双渠道发行工具

适用于 **macOS** 的可复用 XcodeGen 配置与纯 Python 工具：一套源码、两个轻量应用 target，直发版包含 Sparkle，商店版不包含 Sparkle。[调研与设计依据](RESEARCH.md) · [English](README.md)。

这不是另一套编辑器、运行时更新框架或完整发布系统。NeatEditor 现有应用 target、用户数据和发布方式不变。示例程序只输出所属渠道并退出，没有界面。

## 组件

- `dual-channel.yml`：共享配置模板；只有直发 target 依赖 Sparkle，只有商店模板默认启用沙盒。分别明确配置两个渠道在 Debug、Release 下的编译条件，避免同一 target 的分配置设置覆盖基础设置。
- `distribution.py`：只读规划 `plan`、本地归档与导出 `build`、实际产物检查 `audit`。
- `example/`：两个 target 的最小示例和各渠道导出配置。
- `test_distribution.py`：不使用用户数据或凭据的标准库测试。真实构建验收见 [VERIFICATION.md](VERIFICATION.md)。

## 安装

需要 macOS、Xcode、XcodeGen 和 Python 3.11+。先确保 `~/.local/bin` 存在且位于 PATH，再在本仓库根目录运行：

```bash
chmod +x tools/macos-distribution/distribution.py
ln -s "$PWD/tools/macos-distribution/distribution.py" "$HOME/.local/bin/macos-distribution"
macos-distribution version
```

安装不会覆盖已有同名工具；冲突时先检查旧安装，不要强制覆盖。也可以直接运行 `python3 /path/to/distribution.py`。源码检出目录是唯一维护源，不需要 PyPI 依赖或复制凭据。需要可复现构建时使用固定提交的检出目录。

## 在其他应用中使用

参考 [`example/project.yml`](example/project.yml)，以 `relativePaths: false` 引用 `dual-channel.yml`。其他应用可以直接引用固定检出目录的绝对路径，无需各自维护一份工具。独立克隆的消费者和 CI 必须明确准备该工具目录，不能假定其他机器具有本机目录布局。

1. 提供应用名、bundle ID、源码目录、应用分类（`app_category`）、最低系统、版本、团队、本地化和实际 Info.plist 属性；直发版还需要真实 HTTPS 更新源和 Sparkle 公钥。示例值只是占位符。已有应用必须合并原有文件类型等配置，不能用示例覆盖。
2. 两个应用 target 分别使用 `DistributionDirect` 和 `DistributionAppStore` 模板。不要把 Sparkle 加到共同模板中，也不要在链接后删除框架。
3. 使用 `#if DIRECT_DISTRIBUTION` 包住更新框架导入和更新控件，商店版使用 `APP_STORE`。保留更新重启前保存等产品行为；已有共享更新组件继续复用，不由本工具替代。
4. 商店模板只授予沙盒，不默认授予文件访问、联网、App Groups 或临时例外。应用须按实际能力增加权限并验证真实授权路径。沙盒直发版也可行，但需要额外配置 Sparkle 沙盒支持，本示例不启用该组合。
5. 将小型 JSON/ExportOptions 示例放到消费者仓库，填写两个导出配置的真实 `teamID`、签名身份、描述文件和 target 团队，运行 `xcodegen generate`。生成项目与 plist 必须匹配已提交输入。密钥只保留在既有钥匙串或 Apple 凭据存储中。
6. 明确采用相同还是不同 bundle ID，以及数据迁移方案。同 ID 不代表自动共享数据，也不代表可以安全并存；验收示例时不要覆盖已安装的同 ID 应用。

## 规划和构建

完成应用配置后，在消费者仓库运行：

```bash
macos-distribution plan --config distribution.json --out build/distribution/run-001
macos-distribution build --config distribution.json --out build/distribution/run-001 --dry-run
macos-distribution build --config distribution.json --out build/distribution/run-001
```

`--channel` 可选 `direct`、`app-store` 或默认 `all`。JSON 中的路径相对于 JSON 文件，不能越出其所在目录；`--out` 相对于调用位置，建议使用 Git 忽略的目录。

规划与 dry-run 只读取本地配置，不创建输出、不启动 Xcode、不访问钥匙串或网络。真实构建要求干净的已提交源码，分别生成 arm64 + x86_64 归档并导出到不同目录，检查源码和导出配置是否发生变化，拒绝覆盖已有输出。不会 stash、删除源码或自动重试不确定的操作。批次遇错停止，回执保留正在处理的渠道、阶段及已导出的结果；重试须先检查保留结果并选择新的输出目录。

结果包含各渠道的 `.xcarchive`、`.xcresult`、完整归档/导出日志、导出目录与 `receipt.json`。必须检查完整诊断及警告。`exported_not_published` 只表示已导出，不能视为发布验收完成。中断会保留产物与回执，目前不自动续跑。工程构建阶段属于可信输入，执行前须检查自定义脚本的额外副作用；本工具不能把任意工程中的脚本关进沙盒。

商店导出可能是 `.pkg`，不是直接运行的 `.app`。工具检查已签名的归档及实际存在的导出 `.app`，但不解包验签导出商店安装包，始终保留 `requires_store_validation: true`。必须另行完成 Xcode/App Store Connect 验证及 TestFlight/商店实际路径验收。本工具不传 `-allowProvisioningUpdates`，签名材料需单独准备。

直发导出后仍需走产品原有的公证、装订、DMG/更新 ZIP、appcast 和发布流程；商店导出后仍需验证、上传和审核。本工具不上传、不发布、不公证、不安装、不修改商店账号记录，也不迁移用户数据。错误导出方法或 `destination: upload` 会在写入前拒绝。

## 检查实际产物

```bash
macos-distribution audit --app /path/to/App.app --channel app-store --bundle-id com.example.App
macos-distribution audit --app /path/to/Development.app --channel app-store --bundle-id com.example.App --stage development
```

默认按正式发行检查：实际包签名、所有嵌套 Mach-O 签名、主程序双架构、不带调试权限及渠道签名要求。商店版必须具有签名中的沙盒权限，不能包含 Sparkle 框架、Sparkle 动态链接或 `SU*` 更新配置；直发版必须包含并链接 Sparkle。采用其他更新框架的应用需要独立确定对应检查策略。

`--stage development` 明确放宽发行签名、双架构及调试权限检查，仅用于验证开发产物的渠道隔离，不能用来绕过正式检查。结果始终标明检查阶段及未覆盖的功能、公证、商店验收范围。通过该检查不证明文件授权、自动更新、数据迁移或商店审核已成功。

## 命令契约与测试

没有交互提示。终端默认显示可读结果；`--json` 或非 TTY 输入/输出会在 stdout 返回 `{ok,data,error,meta}`，进度写入 stderr。`--json` 位于子命令之前。退出码：0 成功，1 执行/检查失败，2 参数或配置错误，3 路径不存在，4 权限错误，5 输出已存在或源码不干净/变化。没有另外实现登录流程，签名或导出失败保留原生诊断。

```bash
python3 -m unittest discover -s tools/macos-distribution -p 'test_*.py' -v
ruff check tools/macos-distribution
```

测试使用一次性夹具，覆盖双渠道、dry-run、错误返回、配置/路径检查、源码与选项变化、失败产物保留及渠道隔离反例。真实原生构建覆盖与限制单独记录；模拟子进程测试不等于 Apple 导出或审核通过。
