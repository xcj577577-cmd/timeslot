# 时隙 · GitHub 发布步骤

仓库目前只有本地 `main`，还没有 remote。按下面做完，源码和 2.2.0 发行包就会出现在 GitHub。

## 发布什么

| 位置 | 内容 |
| --- | --- |
| 仓库 `main` | 源码、测试、文档、品牌资产 |
| GitHub Release `v2.2.0` | ZIP、DMG、SHA-256、更新日志 |

不要把 `.build/`、`work/`、本机 App Group 快照或用户倒计时数据推进仓库。ZIP/DMG 只作为 Release 附件。

当前发行包是 **2.2.0（Build 52）**，对应提交 `93073a2`（产品化）和 `d1f57d3`（GitHub-only 文档）。`main` 上若还有金色楔形等后续提交，不要打进 `v2.2.0` 标签。

## 一次准备

本机还没有 `gh`，也没有 SSH 公钥。任选一种登录方式：

```bash
brew install gh
gh auth login
```

或到 GitHub 添加 SSH 公钥后再用 `git@github.com:...`。

建议先改提交身份，避免公开历史上继续出现 `Codex <codex@local>`：

```bash
git config user.name "你的名字"
git config user.email "你的邮箱"
```

历史提交已经是 `Codex <codex@local>`。仓库从未推送过，若要公开前改掉作者，可在确认身份后对 `main` 做一次 `git rebase` 改作者；不改也不影响发布，只是 GitHub 上会显示这个名字。

## 创建仓库并推送

在仓库根目录：

```bash
cd /Users/kokoneed/Documents/Codex/2026-07-27/xianz

# 公开仓库。若要先私有，把 --public 改成 --private
gh repo create timeslot --public --source=. --remote=origin --description "时隙：原生 macOS 倒计时与专注工具"

git push -u origin main
```

没有 `gh` 时，先在 GitHub 网页新建空仓库（不要勾选 README / LICENSE），再：

```bash
git remote add origin https://github.com/<你的用户名>/timeslot.git
git push -u origin main
```

仓库名可用 `timeslot` 或 `xianz`。README 对外名称是「时隙」，英文用 TimeSlot 即可。

## 打标签并上传 2.2.0

标签打在 GitHub-only 文档提交上，与现有 ZIP/DMG 一致：

```bash
git tag -a v2.2.0 d1f57d3 -m "时隙 2.2.0 (Build 52)"
git push origin v2.2.0

gh release create v2.2.0 \
  --title "时隙 2.2.0" \
  --notes-file outputs/RELEASE-NOTES-v2.2.0.md \
  "outputs/时隙-macOS-v2.2.0-build52.zip" \
  "outputs/时隙-macOS-v2.2.0-build52.dmg" \
  outputs/SHA256SUMS-v2.2.0-build52.txt \
  "outputs/使用说明.md" \
  "outputs/隐私政策.md"
```

没有 `gh` 时，在 GitHub 网页用 `v2.2.0` 标签新建 Release，上传上面五个文件，正文贴 `outputs/RELEASE-NOTES-v2.2.0.md`。

## 校验

```bash
shasum -a 256 -c outputs/SHA256SUMS-v2.2.0-build52.txt
```

在干净的 macOS 14+ 上下载 ZIP 或 DMG，核对 SHA-256，再拖入「应用程序」。当前包是 Apple Development 签名、未经公证：首次打开可能被 Gatekeeper 拦住。不要教用户 `xattr -cr` 去隔离属性。需要公开分发给陌生人时，再补 Developer ID 与公证。

Issue #1 已记录这一情况。感谢 @ixhsia 提供复现信息；正式解决方式是使用 Developer ID Application 签名并完成 Apple 公证，不能把关闭 Gatekeeper 或删除 quarantine 属性当作正式方案。

## 仓库设置建议

- About：`原生 macOS 倒计时与番茄钟，桌面小组件驻留在桌面层。`
- Topics：`macos` `swift` `widgetkit` `pomodoro` `countdown`
- 勾选 Releases
- 隐私政策暂用仓库里的 `outputs/隐私政策.md`；有 HTTPS 页面后再改 README 和 About
- 支持邮箱还没有，不要先写假地址

## 公开前已处理

- 产品化报告里的本机路径和真实倒计时标题已改成中性描述
- `.gitignore` 已排除 `.build/`、用户态、ZIP/DMG、`work/`
- 授权文件只含 App Sandbox 与 App Group，没有网络权限
- 校验和与本地 `outputs/时隙-macOS-v2.2.0-build52.{zip,dmg}` 一致
