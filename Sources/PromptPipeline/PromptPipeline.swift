import Foundation
import CryptoKit
import Darwin

public struct EnrichedPrompt: Sendable{
    public let userQuery: String
    public let astContext: String?
    public let ragContext: String?

    public var rendered: String {
        var parts: [String] = []
        if let ast = astContext {
            parts.append("### AST Context\n\(ast)")
        }
        if let rag = ragContext {
            parts.append("### Retrieved Context\n\(rag)")
        }
        parts.append("### User Query\n\(userQuery)")
        return parts.joined(separator: "\n\n")
    }
}

public enum PromptPipelineError: Error, LocalizedError {
    case bundleNotFound(String)
    case decryptionFailed(String)
    case loadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .bundleNotFound(let name):  return "Asset bundle '\(name)' not found in app bundle."
        case .decryptionFailed(let msg): return "Decryption failed: \(msg)"
        case .loadFailed(let msg):       return "Asset load failed: \(msg)"
        }
    }
}

/// Decrypts and dlopen-loads the AST and RAG dylibs at launch time.
/// Holds the dlopen handles for the lifetime of the app.
public final class AssetStore {

    // dlopen handles — kept alive so the dylibs stay mapped in memory
    private var astHandle: UnsafeMutableRawPointer?
    private var ragHandle: UnsafeMutableRawPointer?

    public private(set) var astQuery: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>)?
    public private(set) var ragQuery: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>)?

    public init() {}

    /// Call once during launch, before the TUI starts.
    public func load(masterAESKey: SymmetricKey, resourceBundle: Bundle) throws {
        astHandle = try decryptAndLoad(bundleName: "ast", key: masterAESKey, symbol: "ast_query", bundle: resourceBundle, into: &astQuery)
        ragHandle = try decryptAndLoad(bundleName: "rag", key: masterAESKey, symbol: "rag_query", bundle: resourceBundle, into: &ragQuery)
    }

    deinit {
        if let h = astHandle { dlclose(h) }
        if let h = ragHandle { dlclose(h) }
    }

    private func decryptAndLoad<F>(
        bundleName: String,
        key: SymmetricKey,
        symbol: String,
        bundle: Bundle,
        into target: inout F?
    ) throws -> UnsafeMutableRawPointer? {
        guard let bundleURL = bundle.url(forResource: bundleName, withExtension: "bundle") else {
            throw PromptPipelineError.bundleNotFound("\(bundleName).bundle")
        }

        // 2. Read and decrypt (AES-GCM; first 12 bytes are the nonce)
        let encrypted = try Data(contentsOf: bundleURL)
        guard encrypted.count > 28 else {
            throw PromptPipelineError.decryptionFailed("Bundle '\(bundleName)' is too small to contain a nonce.")
        }
        let sealedBox = try AES.GCM.SealedBox(combined: encrypted)
        let plaintext: Data
        do {
            plaintext = try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw PromptPipelineError.decryptionFailed(error.localizedDescription)
        }

        // 3. Write decrypted dylib to a uniquely-named temp file
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(bundleName)-\(UUID().uuidString).dylib")
        do {
            try plaintext.write(to: tmp, options: .atomic)
        } catch {
            throw PromptPipelineError.loadFailed("Could not write temp dylib: \(error.localizedDescription)")
        }

        // 4. dlopen the temp file
        guard let handle = dlopen(tmp.path, RTLD_LOCAL | RTLD_NOW) else {
            let reason = String(cString: dlerror())
            try? FileManager.default.removeItem(at: tmp)
            throw PromptPipelineError.loadFailed("dlopen failed for '\(bundleName)': \(reason)")
        }

        // 5. Delete the temp file immediately — dyld keeps it mapped via fd
        try? FileManager.default.removeItem(at: tmp)

        // 6. Resolve the symbol
        guard let sym = dlsym(handle, symbol) else {
            dlclose(handle)
            throw PromptPipelineError.loadFailed("Symbol '\(symbol)' not found in '\(bundleName)'.")
        }
        target = unsafeBitCast(sym, to: F.self)

        return handle
    }
}

public class PromptPipeline {

    private let assets: AssetStore

    public init(assets: AssetStore) {
        self.assets = assets
    }

    public func process(userQuery: String) throws -> EnrichedPrompt {
        guard let astContext = runQuery(assets.astQuery, input: userQuery, label: "AST"),
            let ragContext = runQuery(assets.ragQuery, input: userQuery, label: "RAG")
        else {
            throw PromptPipelineError.loadFailed("Query functions not loaded — dlsym likely failed")
        }
        return EnrichedPrompt(userQuery: userQuery, astContext: astContext, ragContext: ragContext)
    }

    private func runQuery(
        _ fn: (@convention(c) (UnsafePointer<CChar>) -> UnsafePointer<CChar>)?,
        input: String,
        label: String
    ) -> String? {
        guard let fn else { return nil }
        return input.withCString { ptr in
            String(cString: fn(ptr))
        }
    }
}
