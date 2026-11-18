import SwiftUI
import AppKit

@main
struct HarborApp: App {
    @NSApplicationDelegateAdaptor(HarborAppDelegate.self) private var appDelegate
    @StateObject private var model = HarborModel()
    var body: some Scene {
        WindowGroup(id: "main") { MiniView(model: model).background(MainWindowLifecycle()).onAppear { if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) { NSApplication.shared.applicationIconImage = icon } }.frame(width: 380, height: 580).preferredColorScheme(.dark) }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
            .commands { CommandGroup(replacing: .newItem) {} }
        MenuBarExtra {
            HarborMenu(model: model)
        } label: {
            Label(model.running ? "Harbor FTP · 运行中" : "Harbor FTP · 已停止", systemImage: model.running ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}
struct HarborMenu: View {
    @ObservedObject var model: HarborModel
    @Environment(\.openWindow) private var openWindow
    private func showMain() {
        NSApplication.shared.setActivationPolicy(.regular)
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    var body: some View {
        Text("Harbor FTP")
        Text(model.running ? "运行中 · \(model.connections) 个连接" : "服务已停止")
        if model.running { Text(model.endpoint) }
        Divider()
        Button(model.stopping ? "正在停止…" : model.running ? "停止服务" : "启动服务") {
            model.toggle()
            if model.error != nil { showMain() }
        }.disabled(model.stopping)
        Button("复制连接地址") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(model.endpoint, forType: .string)
        }.disabled(!model.running)
        Divider()
        Button("当前连接（\(model.connections)）") { model.selected = "当前连接"; showMain() }
        ForEach(model.connectedClients.prefix(5)) { client in
            Text("\(client.ip) · \(client.username ?? "未登录")")
        }
        Button("打开主窗口") { showMain() }
        Button("查看活动日志") { model.selected = "活动日志"; showMain() }
        Divider()
        Button("退出 Harbor FTP") {
            model.server.stop()
            NSApplication.shared.terminate(nil)
        }
    }
}
final class HarborModel: ObservableObject {
    @Published var selected = "共享空间"
    @Published var copied = false
    @Published var colorBackground = UserDefaults.standard.object(forKey: "colorBackground") as? Bool ?? true {
        didSet { UserDefaults.standard.set(colorBackground, forKey: "colorBackground") }
    }
    @Published var folder = UserDefaults.standard.string(forKey: "folder") ?? ""
    @Published var port = UserDefaults.standard.string(forKey: "port") ?? "2121"
    @Published var username = UserDefaults.standard.string(forKey: "username") ?? "harbor"
    @Published var password = ""
    @Published var anonymous = false
    @Published var writable = true
    @Published var running = false
    @Published var stopping = false
    @Published var connectedClients: [FTPConnection] = []
    var connections: Int { connectedClients.count }
    @Published var logs: [String] = []
    @Published var error: String?
    let server = FTPServer()
    var address: String {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return "127.0.0.1" }
        defer { freeifaddrs(pointer) }
        var item = pointer
        while let current = item {
            let value = current.pointee
            if let addr = value.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), String(cString: value.ifa_name).hasPrefix("en") {
                let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { String(cString: inet_ntoa($0.pointee.sin_addr)) }
                return ip
            }
            item = value.ifa_next
        }
        return "127.0.0.1"
    }
    var endpoint: String { "ftp://\(address):\(port)" }
    init() {
        server.log = { [weak self] message in
            let timestamp = Date()
            DispatchQueue.main.async { self?.append(message, at: timestamp) }
        }
        server.connectionChanged = { [weak self] clients in DispatchQueue.main.async { self?.connectedClients = clients } }
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.server.stop() }
    }
    func append(_ text: String, at timestamp: Date = Date()) {
        let formatter = DateFormatter(); formatter.dateFormat = "HH:mm:ss"
        logs.insert("\(formatter.string(from: timestamp))   \(text)", at: 0)
        if logs.count > 200 { logs.removeLast(logs.count - 200) }
    }
    func choose() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.prompt = "共享此文件夹"
        if panel.runModal() == .OK, let url = panel.url { folder = url.path; UserDefaults.standard.set(folder, forKey: "folder") }
    }
    func toggle() {
        guard !stopping else { return }
        if running {
            stopping = true
            append("正在停止服务，关闭全部连接…")
            DispatchQueue.global().async { [self] in
                server.stop()
                DispatchQueue.main.async { [self] in
                    running = false; stopping = false; connectedClients = []
                    append("服务已停止 · 监听端口及全部传输连接已关闭")
                }
            }
            return
        }
        guard let number = UInt16(port), number >= 1024 else { error = "请输入 1024–65535 之间的端口。"; return }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder, isDirectory: &directory), directory.boolValue else { error = "请先选择一个有效的共享文件夹。"; return }
        guard !username.isEmpty, username != "anonymous", !password.isEmpty else { error = "请设置用户名和密码；用户名不能为 anonymous。"; return }
        do {
            try server.start(FTPConfig(root: URL(fileURLWithPath: folder), port: number, username: username, password: password, anonymous: anonymous, writable: writable))
            running = true; UserDefaults.standard.set(port, forKey: "port"); UserDefaults.standard.set(username, forKey: "username"); append("服务已启动 · \(endpoint)")
        } catch { self.error = "启动失败：\(error)" }
    }
}
struct HarborView: View {
    @ObservedObject var model: HarborModel
    let ink = Color(red: 0.9, green: 0.92, blue: 0.96)
    let green = Color(red: 0.48, green: 0.61, blue: 1.0)
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(nsImage: NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ?? URL(fileURLWithPath: "")) ?? NSImage()).resizable().frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 1) { Text("Harbor").font(.system(size: 23, weight: .bold, design: .rounded)); Text("LOCAL FILE TRANSFER").font(.system(size: 10)).foregroundStyle(.secondary) }
                }.padding(.top, 14)
                VStack(spacing: 9) {
                    nav("共享空间", icon: "square.grid.2x2")
                    nav("当前连接", icon: "person.2")
                    nav("活动日志", icon: "waveform.path")
                }
                Spacer()
                HStack(spacing: 7) {
                    Circle().fill(model.running ? green : Color.gray).frame(width: 6, height: 6)
                    Text(model.running ? "服务运行中" : "服务未启动").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("HARBOR FTP  /  0.4.2").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            }.padding(22).frame(width: 200).background(Color(red: 0.065, green: 0.075, blue: 0.095))
            Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(model.selected).font(.system(size: 24, weight: .semibold))
                            Text(model.selected == "共享空间" ? "管理本机 FTP 服务与文件访问权限" : model.selected == "当前连接" ? "查看连接来源、登录账号与当前活动" : "查看当前会话中的连接与文件活动。").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("本机服务", systemImage: "desktopcomputer").font(.system(size: 11)).padding(9).background(Color.white.opacity(0.05), in: Capsule())
                    }
                    if model.selected == "共享空间" {
                        statusCard
                        VStack(alignment: .leading, spacing: 13) {
                            sectionTitle("共享文件夹", subtitle: "此文件夹是客户端可访问的根目录", icon: "folder")
                            HStack(spacing: 14) {
                                Image(systemName: "folder.fill").font(.system(size: 32)).foregroundStyle(green)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(model.folder.isEmpty ? "选择你的共享空间" : URL(fileURLWithPath: model.folder).lastPathComponent).font(.system(size: 14, weight: .semibold))
                                    Text(model.folder.isEmpty ? "选择一个文件夹，开始分享" : model.folder).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                                }
                                Spacer()
                                Button("选择文件夹…", action: model.choose).disabled(model.running)
                            }.padding(16).background(Color(red: 0.085, green: 0.10, blue: 0.13), in: RoundedRectangle(cornerRadius: 12))
                        }.card()
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 13) {
                                sectionTitle("连接设置", subtitle: "使用这些信息连接你的 Mac", icon: "slider.horizontal.3")
                                field("监听端口", text: $model.port)
                                field("用户名", text: $model.username)
                                VStack(alignment: .leading, spacing: 6) { Text("密码").font(.system(size: 11)).foregroundStyle(.secondary); SecureField("每次打开应用后填写", text: $model.password).textFieldStyle(.plain).padding(9).background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08), lineWidth: 1)) }
                            }.disabled(model.running).card()
                            VStack(alignment: .leading, spacing: 13) {
                                sectionTitle("访问权限", subtitle: "决定访客可以做什么", icon: "lock.shield")
                                Toggle("允许上传与修改", isOn: $model.writable).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small).tint(green)
                                Text("关闭后，账号仅可浏览和下载。").font(.system(size: 11)).foregroundStyle(.secondary)
                                Divider()
                                Toggle("允许匿名访问", isOn: $model.anonymous).font(.system(size: 12)).toggleStyle(.switch).controlSize(.small).tint(green)
                                Text("匿名访客始终仅有读取权限。").font(.system(size: 11)).foregroundStyle(.secondary)
                                Label("FTP 不加密，适用于可信局域网。", systemImage: "info.circle").font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 5)
                            }.disabled(model.running).card()
                        }
                    }
                    if model.selected == "当前连接" { connectionsCard } else { logCard }
                }.padding(28).background(QuietScrollStyle())
            }.background(Color(red: 0.085, green: 0.095, blue: 0.12))
        }.foregroundStyle(ink).alert("请检查设置", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("好的") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    func nav(_ title: String, icon: String) -> some View {
        Button { model.selected = title } label: {
            HStack(spacing: 12) { Image(systemName: icon); Text(title).font(.system(size: 13, weight: .medium)); Spacer() }.padding(13).foregroundStyle(model.selected == title ? green : .secondary).background(model.selected == title ? green.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
    var statusCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                HStack(spacing: 8) { Circle().fill(model.running ? Color.green : Color.white.opacity(0.4)).frame(width: 7, height: 7); Text(model.running ? "服务正在运行" : "服务已停止").font(.system(size: 13, weight: .medium)) }
                Spacer()
                Button { model.selected = "当前连接" } label: { Label("\(model.connections) 个连接", systemImage: "chevron.right").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)) }.buttonStyle(.plain)
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.running ? model.endpoint : "准备连接").font(.system(size: 24, weight: .medium, design: .rounded)).textSelection(.enabled)
                    Text(model.running ? "在 FTP 客户端中输入上方地址即可连接" : "选择共享目录并配置账号，即可启动服务。") .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button(action: model.toggle) { Label(model.stopping ? "正在停止…" : model.running ? "停止服务" : "启动服务", systemImage: model.running ? "stop.fill" : "play.fill").font(.system(size: 12, weight: .semibold)).padding(.horizontal, 17).padding(.vertical, 12).background(green, in: RoundedRectangle(cornerRadius: 9)).foregroundStyle(Color.white) }.buttonStyle(.plain).disabled(model.stopping)
            }
            if model.running {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.endpoint, forType: .string); model.copied = true; DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.copied = false } } label: { Label(model.copied ? "已复制" : "复制连接地址", systemImage: model.copied ? "checkmark" : "doc.on.doc").font(.system(size: 11)) }.buttonStyle(.plain)
            }
        }.padding(24).foregroundStyle(.white).background(LinearGradient(colors: [Color(red: 0.15, green: 0.19, blue: 0.29), Color(red: 0.105, green: 0.13, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(green.opacity(0.18), lineWidth: 1))
    }
    var connectionsCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("当前连接").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(model.connections) 个会话").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text("同一客户端可能建立多个会话。IP 和登录账号用于识别来源，不代表设备名或真实身份。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if model.connectedClients.isEmpty {
                Label(model.running ? "暂无客户端连接" : "服务已停止，没有在线连接", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 28)
            } else {
                ForEach(model.connectedClients) { client in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer").font(.system(size: 22)).foregroundStyle(green)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(client.ip).font(.system(size: 16, weight: .semibold, design: .monospaced)).textSelection(.enabled)
                                Text(client.username.map { "登录账号 · \($0)" } ?? "尚未登录")
                                    .font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(client.activity).font(.system(size: 12)).foregroundStyle(green).lineLimit(2)
                        }
                        HStack {
                            Text("连接于 \(client.connectedAt.formatted(date: .omitted, time: .standard))")
                            Spacer()
                            Text("会话 \(client.id.uuidString.prefix(8))").fontDesign(.monospaced)
                        }.font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(16).background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }.card()
    }
    var logCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("最近活动").font(.system(size: 14, weight: .semibold)); Spacer(); if model.selected != "活动日志" { Button("查看全部") { model.selected = "活动日志" }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(green) }; if !model.logs.isEmpty { Button("清空") { model.logs.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary) } }
            if model.logs.isEmpty { HStack(spacing: 10) { Image(systemName: "text.alignleft"); Text("尚无活动，启动服务后将在这里显示连接记录。") }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 13) }
            else { ForEach(Array(model.logs.prefix(model.selected == "活动日志" ? 200 : 5).enumerated()), id: \.offset) { _, line in Text(line).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) } }
        }.card()
    }
    func sectionTitle(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) { Image(systemName: icon).foregroundStyle(green); VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 14, weight: .semibold)); Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary) } }
    }
    func field(_ name: String, text: Binding<String>) -> some View { VStack(alignment: .leading, spacing: 6) { Text(name).font(.system(size: 11)).foregroundStyle(.secondary); TextField(name, text: text).textFieldStyle(.plain).padding(9).background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7)).overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.08), lineWidth: 1)) } }
}
private extension View {
    func card() -> some View { self.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Color(red: 0.115, green: 0.13, blue: 0.16), in: RoundedRectangle(cornerRadius: 12)).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.065), lineWidth: 1)) }
}
