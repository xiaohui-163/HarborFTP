<div align="center">
  <img src="Resources/AppIcon.png" alt="Harbor FTP 图标" width="120">
  <h1>Harbor FTP</h1>
  <p>简洁的 macOS 局域网 FTP 服务端</p>
  <p>SwiftUI 原生界面 · 无第三方运行时依赖 · 被动模式 FTP</p>
</div>

> **安全提示：**普通 FTP 不加密账号、密码或传输内容。请仅在可信网络中使用，不要直接暴露到互联网。

## 功能

- 选择本机文件夹，通过 FTP 分享给其他设备
- 使用账号密码登录，可选开启匿名只读访问
- 浏览目录、上传和下载文件，以及创建、删除、重命名文件或目录
- 按需关闭上传与修改，支持中文文件名
- 查看在线会话、当前活动和最近 200 条内存日志
- 关闭主窗口后继续在菜单栏运行；可切换彩色或桌面透色背景

## 系统要求

- macOS 13 或更高版本
- 当前构建脚本和安装包面向 Apple Silicon（arm64）
- 构建需要 Apple Command Line Tools 和 Swift

## 安装与启动

如果仓库中提供了安装包，可在 [`release/`](release/) 中选择 `.dmg` 或 `.pkg`。DMG 打开后将应用拖入“应用程序”；PKG 按安装向导操作。

当前构建使用临时签名，**未经 Apple 公证**，macOS 可能阻止打开。也可以按下面的方法从源码构建。

1. 打开 Harbor FTP，选择要共享的文件夹。
2. 在设置中填写端口、用户名和密码，按需设置写入权限及匿名访问。
3. 点击“启动服务”，记下界面显示的地址。
4. 在客户端选择 **FTP（普通 FTP）**和**被动模式**，输入服务端地址、端口及账号密码连接。

默认端口为 `2121`；服务端接受 `1024–65535` 范围内的端口。客户端和服务端需要网络互通，若无法连接，请检查 IP、端口、防火墙和客户端的被动模式设置。

开启匿名访问后，客户端也可以使用 `anonymous` 登录，且只能读取。若只允许指定账号访问，请关闭匿名访问。设置在服务运行时锁定，修改前需先停止服务。

## 从源码构建

在项目目录执行：

```sh
./scripts/build.sh
open build/HarborFTP.app
```

脚本直接编译 Swift 源码，生成 `build/HarborFTP.app` 并进行本机临时签名。它不会生成 `release/` 中的安装包。

## 项目结构

| 路径 | 说明 |
| --- | --- |
| [`Sources/HarborApp.swift`](Sources/HarborApp.swift) | 应用入口、共享状态和菜单栏 |
| [`Sources/MiniView.swift`](Sources/MiniView.swift) | 主窗口 SwiftUI 界面 |
| [`Sources/FTPServer.swift`](Sources/FTPServer.swift) | FTP 协议、Socket 与文件操作 |
| [`Sources/WindowLifecycle.swift`](Sources/WindowLifecycle.swift) | 窗口和 Dock 生命周期 |
| [`Resources/`](Resources/) | 应用图标 |
| [`scripts/`](scripts/) | 构建和资源制作脚本 |
| [`tests/`](tests/) | FTP 集成与回归测试 |

## 测试

在 macOS 上执行：

```sh
swiftc -module-cache-path .build/module-cache Sources/FTPServer.swift tests/ServerHarness.swift -o .build/ftp-test
python3 tests/integration.py
python3 tests/stop_and_logs.py
python3 tests/connections.py
```

测试需要 Python 3 和本机网络监听权限；集成测试使用 `22121` 端口及临时文件夹。如尚未构建过项目，请先运行 `./scripts/build.sh`，以创建测试所需的 `.build` 目录。

## 工作方式与限制

- 使用 IPv4 和被动模式（PASV/EPSV）；不支持 FTPS、SFTP、主动模式、断点续传或 NAT 自动配置。
- 密码仅保存在进程内存中，退出后需重新填写；日志也只保存在内存中，退出后清空。
- 文件夹、端口、用户名和彩色背景偏好会保存；匿名访问与写入权限在重启后恢复默认值。
- 停止服务会关闭连接并等待会话退出。上传先写入临时文件，正常完成后再替换目标文件。
- 路径检查可阻止常规目录穿越和指向共享目录外的符号链接；尚未针对本机恶意并发修改路径进行完整安全审计。
- FTP 上传的正常结束不一定能证明客户端发送了预期的完整文件；下载完成表示服务端已写入连接，不代表客户端已保存到磁盘。
