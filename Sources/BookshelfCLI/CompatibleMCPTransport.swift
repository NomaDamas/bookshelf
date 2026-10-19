import Foundation
import BookshelfCore
import MCP

actor CompatibleMCPTransport: Transport {
    private let transport = StdioTransport()
    // Reuse the SDK's default no-op logger without adding a separate logging dependency.
    nonisolated let logger = StdioTransport().logger
    func connect() async throws { try await transport.connect() }
    func disconnect() async { await transport.disconnect() }
    func send(_ data: Data) async throws { try await transport.send(data) }
    func receive() -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let messages = await transport.receive()
                    for try await message in messages {
                        continuation.yield(MCPHandshakeCompatibility.ignoringUnsupportedExtensions(message))
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
