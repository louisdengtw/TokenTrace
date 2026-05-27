import SwiftUI

/// Left-aligned horizontal flow that wraps to new rows when the container's
/// proposed width is exceeded. Each subview gets its natural width (the
/// layout never forces a child to shrink) — items that don't fit the
/// remaining row width jump to the next row.
///
/// Used by the Claude Code tab's chart legend so chips never truncate
/// to meaningless 2-3 character stubs at narrow window widths.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 14
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let arranged = arrange(maxWidth: maxWidth, subviews: subviews)
        return CGSize(width: arranged.contentWidth, height: arranged.contentHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arranged = arrange(maxWidth: bounds.width, subviews: subviews)
        for slot in arranged.slots {
            let pt = CGPoint(x: bounds.minX + slot.origin.x, y: bounds.minY + slot.origin.y)
            subviews[slot.index].place(at: pt, anchor: .topLeading, proposal: .unspecified)
        }
    }

    // MARK: - Internal arrangement

    private struct Slot { let index: Int; let origin: CGPoint }
    private struct Arrangement {
        let slots: [Slot]
        let contentWidth: CGFloat
        let contentHeight: CGFloat
    }

    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> Arrangement {
        var slots: [Slot] = []
        var rowItems: [(idx: Int, size: CGSize)] = []
        var rowY: CGFloat = 0
        var rowMaxHeight: CGFloat = 0
        var widest: CGFloat = 0
        var rowWidth: CGFloat = 0

        func flushRow() {
            var x: CGFloat = 0
            for item in rowItems {
                slots.append(Slot(index: item.idx, origin: CGPoint(x: x, y: rowY)))
                x += item.size.width + horizontalSpacing
            }
            widest = max(widest, max(0, x - horizontalSpacing))
            rowY += rowMaxHeight + verticalSpacing
            rowItems.removeAll(keepingCapacity: true)
            rowMaxHeight = 0
            rowWidth = 0
        }

        for idx in subviews.indices {
            let size = subviews[idx].sizeThatFits(.unspecified)
            let needed = rowItems.isEmpty ? size.width : rowWidth + horizontalSpacing + size.width
            if needed > maxWidth, !rowItems.isEmpty {
                flushRow()
            }
            rowWidth = rowItems.isEmpty ? size.width : rowWidth + horizontalSpacing + size.width
            rowItems.append((idx, size))
            rowMaxHeight = max(rowMaxHeight, size.height)
        }
        if !rowItems.isEmpty {
            flushRow()
        }
        return Arrangement(
            slots: slots,
            contentWidth: widest,
            contentHeight: max(0, rowY - verticalSpacing)
        )
    }
}
