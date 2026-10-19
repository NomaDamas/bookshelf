import Foundation

public enum MCPHandshakeCompatibility {
    /// SDK 0.12.1 decodes experimental client capabilities as [String: String].
    /// Codex advertises object-valued extensions; this server does not implement them.
    /// Ignore only those unsupported extensions, keeping standard capabilities intact.
    public static func ignoringUnsupportedExtensions(_ data: Data) -> Data {
        guard var message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              message["method"] as? String == "initialize",
              var params = message["params"] as? [String: Any],
              var capabilities = params["capabilities"] as? [String: Any],
              let experimental = capabilities["experimental"] as? [String: Any],
              experimental.values.contains(where: { !($0 is String) }) else { return data }
        let supported = experimental.filter { $0.value is String }
        if supported.isEmpty { capabilities.removeValue(forKey: "experimental") }
        else { capabilities["experimental"] = supported }
        params["capabilities"] = capabilities; message["params"] = params
        return (try? JSONSerialization.data(withJSONObject: message)) ?? data
    }
}
