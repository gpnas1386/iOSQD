# 内网电视遥控器（iOS 版 / TrollStore 巨魔安装）

原生 iPhone 遥控 **Android TV / Google TV** 的应用，基于 Google 官方 **Android TV Remote Protocol v2**。无需红外、无需 ADB、无需开发者模式，手机与电视连同一 Wi-Fi 即可遥控。

> 目标系统：**iOS 16.0 – 16.6.1**（TrollStore 2 支持范围）；协议层兼容 iOS 13+。
> 适用电视：Android TV / Google TV / 安卓系统智能电视（小米、索尼、海信、TCL、NVIDIA Shield、Chromecast with Google TV 等）。LG WebOS、三星 Tizen 不支持。

## 功能

| 功能 | 说明 |
|------|------|
| 设备自动发现 | Bonjour/mDNS 扫描 `_androidtvremote2._tcp` 自动列出内网电视 |
| 手动连接 | 输入电视 IP 直接连接 |
| PIN 配对 | 首次连接输入电视显示的 6 位配对码，之后自动重连 |
| 方向键 + OK | 圆形导航盘，长按连续移动 |
| 系统按键 | 返回 / 主页 / 菜单 / 设置 / 输入源 / 搜索 / 语音助手 |
| 音量 / 静音 | 长按连续调节 |
| 频道 / 数字键 | 频道切换与 0-9 数字输入 |
| 媒体播放 | 播放暂停 / 上一个 / 下一个 / 快退 / 快进 |
| 文字输入 | 发送文字到电视输入框（搜索框等） |
| 打开应用/链接 | 输入包名或网址直接打开 |
| 电源 | 开关机 / 待机唤醒 |

## 发现机制（v1.2.0 起）

App 会**同时**用三条通道找电视，任意一条命中即可：

| 通道 | 协议 | 覆盖范围 |
|------|------|----------|
| SSDP | UDP 1900 · M-SEARCH（UPnP） | 几乎所有智能电视（TCL / Roku / Google TV / 索尼 / 三星 / LG） |
| TCL | UDP 6537 广播 | TCL / 雷鸟国产系统 |
| Bonjour | mDNS `_androidtvremote2/_androidtvremote` | Google TV / Android TV |

找到 IP 后，App 会**自动探测该电视开放的遥控端口**（6466 / 6553 / 8060 / 5555 / 8009 …），据此判断用哪套协议，并在设备列表里打标签。

### 首屏诊断面板

打开 App 首屏就能看到：

- **本机 Wi-Fi IP**——先确认手机真的连在 Wi-Fi 上，且与电视同一网段
- **SSDP / TCL / Bonjour** 三路各发现几台
- **诊断日志**（点开折叠区）——记录每一步：广播发到哪些地址、收到什么响应、端口探测结果

扫不到时，**把诊断日志截图发出来**就能精确定位卡在哪一环。

## 构建方式

iOS 应用必须用 macOS + Xcode 编译（无法在 Linux/Windows 直接编译）。**没有 Mac 也能出 IPA**——用方案 B 在 GitHub 云端免费构建即可。

### 方案 A：本地 Mac 构建（一条命令出 IPA）

```bash
brew install xcodegen        # 可选：brew install ldid（用于预签名）
cd tv-remote-ios
bash build.sh
```

脚本会自动：生成 Xcode 工程 → 构建无签名 Release App → 打包成 **`TVRemote.ipa`**。

> 如需修改应用名 / Bundle ID，编辑 `project.yml` 后重新运行。

### 方案 B：无 Mac —— GitHub Actions 云端构建（免费，推荐）

原理：GitHub 提供免费的 macOS 云端机器，工程里的 `.github/workflows/build.yml` 会自动完成「生成工程 → 编译 → 打包 IPA」，你只需下载产物，全程无需本地 Mac。

**一次性准备（约 3 分钟）：**

1. 注册 [GitHub](https://github.com) 账号（免费）。
2. 新建仓库：点右上角 **+ → New repository**，仓库名随意（如 `tv-remote-ios`），可见性选 **Public（公开，免费额度无限）**。
3. 把本目录所有文件上传到仓库，两种方式任选：
   - **网页上传**：进仓库页，点 **uploading an existing file**，把本目录全部文件拖进去提交；
   - **命令行**：
     ```bash
     cd tv-remote-ios
     git init && git add -A && git commit -m "tv remote"
     git branch -M main
     git remote add origin https://github.com/<你的用户名>/tv-remote-ios.git
     git push -u origin main
     ```

**构建并下载 IPA（以后每次改代码都这么做）：**

1. 打开仓库 **Actions** 标签页 → 左侧选 **Build TVRemote IPA** → 点 **Run workflow** 按钮 → 再次点 **Run workflow** 确认。
2. 等待黄色圆点变成绿色 ✓（约 5–10 分钟）。
3. 点进这次运行，往下拉到 **Artifacts** 区，下载 **TVRemote-ipa**。
4. 解压下载的 zip，得到 **`TVRemote.ipa`**，按下方步骤传到手机安装。

> 上传后若 Actions 菜单还没出现该工作流，刷新页面即可；`build.yml` 同时支持推代码自动构建和手动构建。

## 安装到 iPhone（巨魔 TrollStore）

1. 确认 iPhone 为 **iOS 16.0 – 16.6.1** 且已装好 **TrollStore 2**（巨魔商店）。
2. 把 `TVRemote.ipa` 传到手机（AirDrop / 隔空投送 / 网盘 / 爱思助手均可）。
3. 打开 **TrollStore**，点右上角 **+** → **Install IPA File**，选中该 IPA。
4. 点 **Install** 安装，桌面出现「电视遥控」图标即完成，**永久有效、无需续签**。

> 首次打开 App，iOS 会弹「本地网络」权限，务必点**允许**，否则无法发现/连接电视。

## 使用流程

1. 打开 App，点击右上角**电视图标**进入设备列表。
2. 点「扫描」或直接输入电视 IP 连接。
3. 首次连接时，**电视屏幕**会显示 6 位配对码，输入到手机弹窗完成配对。
4. 配对成功后即可遥控；App 会记住设备，下次打开自动重连。

## 常见问题

**Q：扫描不到电视？**
- 确认电视已开机、与手机在同一 Wi-Fi；路由器若开启「AP 隔离」需关闭。
- 在手机「设置 → 隐私与安全性 → 本地网络」确认已允许本 App。
- 尝试手动输入电视 IP。

**Q：配对码在哪看？**
- 在**电视屏幕**上（不是手机），点击连接后电视会弹出 6 位字母/数字码。

**Q：关机后还能唤醒吗？**
- 电视处于「待机」时遥控服务仍在运行，可直接用电源键唤醒；彻底断电则无法连接。

**Q：提示配对失败？**
- 核对 6 位码重新输入；若电视端重置过遥控服务，重新配对即可。

## 项目结构

```
tv-remote-ios/
├── project.yml              # XcodeGen 工程定义
├── build.sh                 # 一键构建 + 打包 IPA
├── README.md
├── .gitignore
├── .github/
│   └── workflows/
│       └── build.yml        # GitHub Actions 云端免费构建（无需 Mac）
└── TVRemote/
    ├── TVRemoteApp.swift        # App 入口
    ├── ContentView.swift        # 主界面 + 设备列表 + 配对输入
    ├── RemotePadView.swift      # 遥控器界面
    ├── RemoteController.swift   # 发现 + 配对 + 遥控协议
    ├── IdentityStore.swift      # RSA-2048 自签名证书生成
    ├── ASN1.swift               # ASN.1 DER 编解码
    └── Proto.swift              # protobuf 编解码
```

## 技术说明

- 协议：Android TV Remote v2（TLS + protobuf），配对端口 6467、遥控端口 6466，与 Google 官方遥控 App 同协议。
- 证书：首次启动在设备上生成 RSA-2048 自签名身份并存于 Keychain，每个安装独立。
- 隐私：纯局域网直连，无服务器、无账号、无追踪。

> 本工程协议实现依据 Android TV Remote v2 公开规范，参考了开源项目 `AndroidTVRemoteControl`(MIT) 与 `mi-projector-remote-ios`(Apache-2.0) 的协议细节。
