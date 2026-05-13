import Foundation

@_cdecl("rag_query")
public func rag_query(_ input: UnsafePointer<CChar>) -> UnsafePointer<CChar> {
    let result = """
    RAG Context (stub):
      - No chunks retrieved for query: \(String(cString: input))
      - RAG index not yet populated.
    """
    return UnsafePointer(strdup(result))
}
