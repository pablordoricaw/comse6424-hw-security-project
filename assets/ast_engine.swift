import Foundation

@_cdecl("ast_query")
public func ast_query(_ input: UnsafePointer<CChar>) -> UnsafePointer<CChar> {
    let result = """
    AST Context (stub):
      - No symbols resolved for query: \(String(cString: input))
      - AST index not yet populated.
    """
    // Heap-allocate so the pointer outlives this stack frame
    return UnsafePointer(strdup(result))
}
