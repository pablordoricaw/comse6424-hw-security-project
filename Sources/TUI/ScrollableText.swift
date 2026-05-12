import TUIkit

struct ScrollableText: View {
    let lines: [String]
    @Binding var offset: Int
    var onViewportHeight: ((Int) -> Void)? = nil

    var body: Never {
        fatalError("ScrollableText renders via Renderable")
    }
}

extension ScrollableText: Renderable {
    func renderToBuffer(context: RenderContext) -> FrameBuffer {
        // Reserve 1 line for the prompt row below us in the VStack
        let viewportHeight = max(0, context.availableHeight - 1)

        // Report height so the parent can compute maxOffset correctly
        onViewportHeight?(viewportHeight)

        let totalLines = lines.count
        let maxOffset = max(0, totalLines - viewportHeight)
        let clampedOffset = min(offset, maxOffset)

        let visibleLines = Array(lines.dropFirst(clampedOffset).prefix(viewportHeight))
        let padCount = max(0, viewportHeight - visibleLines.count)
        let paddedLines = visibleLines + Array(repeating: "", count: padCount)

        return FrameBuffer(lines: paddedLines)
    }
}
