import SwiftUI
import AppKit

struct GlassBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
/// Fixed palette sampled visually from the user's reference; independent of desktop.
struct HarborColorBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                LinearGradient(colors: [Color(red: 0.43, green: 0.44, blue: 0.36), Color(red: 0.34, green: 0.25, blue: 0.20), Color(red: 0.11, green: 0.23, blue: 0.17)], startPoint: .top, endPoint: .bottom)
                Ellipse().fill(Color(red: 0.63, green: 0.29, blue: 0.10))
                    .frame(width: size.width * 1.05, height: size.height * 0.59)
                    .position(x: size.width * 0.86, y: size.height * 0.47)
                    .blur(radius: 62)
                Ellipse().fill(Color(red: 0.20, green: 0.24, blue: 0.48))
                    .frame(width: size.width * 0.65, height: size.height * 0.43)
                    .position(x: size.width * 0.01, y: size.height * 0.53)
                    .blur(radius: 45)
                Ellipse().fill(Color(red: 0.55, green: 0.43, blue: 0.09))
                    .frame(width: size.width * 0.66, height: size.height * 0.23)
                    .position(x: size.width * 0.05, y: size.height * 0.82)
                    .blur(radius: 40)
                Ellipse().fill(Color(red: 0.09, green: 0.25, blue: 0.16))
                    .frame(width: size.width, height: size.height * 0.30)
                    .position(x: size.width * 0.77, y: size.height * 0.92)
                    .blur(radius: 42)
            }.clipped()
        }
    }
}
struct MiniView: View {
    @ObservedObject var model: HarborModel
    private let accent = Color(red: 0.64, green: 0.74, blue: 1)
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: NSImage(contentsOf: Bundle.main.url(forResource: "AppIcon", withExtension: "icns") ?? URL(fileURLWithPath: "")) ?? NSImage())
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Harbor").font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("FTP · MINI").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                }
                Spacer()
                Circle().fill(model.running ? Color.mint : Color.secondary).frame(width: 6, height: 6)
                Text(model.stopping ? "正在停止" : model.running ? "在线" : "离线").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 4)
            HStack(spacing: 4) {
                tab("共享空间", "共享", "square.stack.3d.up")
                tab("当前连接", "连接", "person.2")
                tab("活动日志", "日志", "waveform.path")
                tab("设置", "设置", "slider.horizontal.3")
            }.padding(5).background(.ultraThinMaterial, in: Capsule()).overlay(Capsule().stroke(.white.opacity(0.12)))
            if model.selected == "设置" {
                settings.padding(2).frame(maxHeight: .infinity, alignment: .top)
            } else {
              ScrollView {
                VStack(spacing: 14) {
                    if model.selected == "共享空间" { home }
                    else if model.selected == "当前连接" { connections }
                    else { logs }
                }.padding(2).background(QuietScrollStyle())
              }
            }
            HStack {
                Image(systemName: "network")
                Text("局域网共享")
                Spacer()
                Text("0.5.5").fontDesign(.monospaced)
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 4)
        }.padding(16).padding(.top, 10)
        .background {
            ZStack {
                if model.colorBackground { HarborColorBackdrop() }
                else { GlassBackdrop() }
                LinearGradient(colors: [Color.indigo.opacity(0.15), .clear, Color.cyan.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }.ignoresSafeArea()
        }
        .alert("请检查设置", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("前往设置") { model.error = nil; model.selected = "设置" }
            Button("好的", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    func tab(_ key: String, _ title: String, _ symbol: String) -> some View {
        Button { model.selected = key } label: {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 14))
                Text(title).font(.system(size: 10, weight: .medium))
            }.frame(maxWidth: .infinity).padding(.vertical, 9)
                .foregroundStyle(model.selected == key ? Color.white : Color.secondary)
                .background(model.selected == key ? Color.white.opacity(0.14) : .clear, in: Capsule())
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    var home: some View {
        VStack(spacing: 14) {
            VStack(spacing: 14) {
                ZStack {
                    Circle().fill(accent.opacity(0.08)).frame(width: 64, height: 64)
                    Circle().stroke(.white.opacity(0.13)).frame(width: 54, height: 54)
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 26, weight: .light)).foregroundStyle(accent)
                }
                VStack(spacing: 7) {
                    Text(model.running ? "共享已就绪" : "随时，轻松连接").font(.system(size: 21, weight: .medium, design: .rounded))
                    Text(model.running ? model.endpoint : "让文件在设备之间自由流动")
                        .font(.system(size: 12, design: model.running ? .monospaced : .default)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Button(action: model.toggle) {
                    Label(model.stopping ? "正在停止…" : model.running ? "停止服务" : "启动服务", systemImage: model.running ? "stop.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(accent.opacity(model.running ? 0.16 : 0.85), in: Capsule())
                        .foregroundStyle(model.running ? Color.white : Color(red: 0.12, green: 0.15, blue: 0.25))
                        .contentShape(Capsule())
                }.buttonStyle(.plain).disabled(model.stopping)
                if model.running {
                    Button {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(model.endpoint, forType: .string)
                        model.copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.copied = false }
                    } label: { Label(model.copied ? "已复制" : "复制地址", systemImage: model.copied ? "checkmark" : "doc.on.doc").font(.system(size: 11)) }.buttonStyle(.plain)
                }
            }.padding(16).glassPanel()
            Button(action: model.choose) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").foregroundStyle(accent).font(.system(size: 24))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.folder.isEmpty ? "选择共享文件夹" : URL(fileURLWithPath: model.folder).lastPathComponent).font(.system(size: 13, weight: .medium))
                        Text(model.folder.isEmpty ? "设置共享的根目录" : model.folder).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(15).glassPanel().contentShape(RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain).disabled(model.running)
            Button { model.selected = "当前连接" } label: {
                HStack { Label("当前连接", systemImage: "person.2"); Spacer(); Text("\(model.connections)"); Image(systemName: "chevron.right") }
                    .font(.system(size: 12)).padding(15).glassPanel().contentShape(RoundedRectangle(cornerRadius: 20))
            }.buttonStyle(.plain)
        }
    }
    var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接设置").font(.system(size: 17, weight: .semibold))
            Group {
            HStack(alignment: .top, spacing: 12) {
                input("端口", value: $model.port).frame(width: 82)
                input("用户名", value: $model.username)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("密码").font(.system(size: 11)).foregroundStyle(.secondary)
                SecureField("本次运行使用的密码", text: $model.password).textFieldStyle(.plain).padding(10).background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            Toggle("允许上传与修改", isOn: $model.writable)
            Toggle("匿名访问（只读）", isOn: $model.anonymous)
            }.disabled(model.running)
            Divider()
            Toggle("彩色背景", isOn: $model.colorBackground)
                .help("开启：固定彩色背景；关闭：桌面透色")
            Text(model.running ? "停止服务后可修改连接设置。" : "FTP 不加密，仅用于可信局域网。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.font(.system(size: 12)).toggleStyle(.switch).controlSize(.small).tint(accent)
            .padding(18).glassPanel()
    }
    func input(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            TextField(label, text: value).textFieldStyle(.plain).padding(10).background(.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        }
    }
    var connections: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("当前连接").font(.system(size: 17, weight: .semibold)); Spacer(); Text("\(model.connections) 个会话").font(.system(size: 11)).foregroundStyle(.secondary) }
            if model.connectedClients.isEmpty { empty("暂无在线连接", icon: "person.2") }
            ForEach(model.connectedClients) { client in
                VStack(alignment: .leading, spacing: 8) {
                    Text(client.ip).font(.system(size: 14, weight: .medium, design: .monospaced))
                    Text("\(client.username ?? "未登录") · \(client.activity)").font(.system(size: 12)).foregroundStyle(accent)
                    Text("\(client.connectedAt.formatted(date: .omitted, time: .standard)) · \(client.id.uuidString.prefix(8))").font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(14).glassPanel()
            }
        }.padding(4)
    }
    var logs: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("活动日志").font(.system(size: 17, weight: .semibold)); Spacer(); Button("清空") { model.logs.removeAll() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary) }
            if model.logs.isEmpty { empty("尚无活动记录", icon: "waveform.path") }
            ForEach(Array(model.logs.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 11, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12).glassPanel()
            }
        }.padding(4)
    }
    func empty(_ title: String, icon: String) -> some View {
        VStack(spacing: 12) { Image(systemName: icon).font(.system(size: 28, weight: .light)); Text(title).font(.system(size: 12)) }
            .foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 60)
    }
}
private extension View {
    func glassPanel() -> some View {
        self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
    }
}
