import Foundation
@main struct Harness {
    static func main() throws {
        let server = FTPServer()
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let config = FTPConfig(root: root, port: 22121, username: "tester", password: "test-password", anonymous: true, writable: true)
        if CommandLine.arguments.contains("--controlled") {
            let logLock = NSLock()
            server.log = { line in
                logLock.lock(); defer { logLock.unlock() }
                FileHandle.standardError.write(Data((line + "\n").utf8))
            }
        }
        try server.start(config)
        print("READY"); fflush(stdout)
        if CommandLine.arguments.contains("--controlled") {
            while let command = readLine() {
                if command == "connections" { print(String(data: try JSONEncoder().encode(server.connectionSnapshot), encoding: .utf8)!) }
                if command == "stop" { server.stop(); print("STOPPED") }
                if command == "start" { try server.start(config); print("STARTED") }
                fflush(stdout)
            }
            server.stop()
        } else { RunLoop.main.run() }
    }
}
