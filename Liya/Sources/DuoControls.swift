import SwiftUI

/// Repositions a group of controls, not its underlying continuous content.
struct DuoControlRegion<Content: View>: View {
    @ViewBuilder let content: (CGSize) -> Content

    var body: some View {
        GeometryReader { geometry in
            let rect = usableRect(in: geometry)
            content(rect.size)
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
        }
    }

    private func usableRect(in proxy: GeometryProxy) -> CGRect {
        let bounds = CGRect(origin: .zero, size: proxy.size)
        guard bounds.width > 0, bounds.height > 0 else { return bounds }
        if #available(iOS 27.1, *) {
            // The rectangle calculations below use physical coordinates, so do not
            // mirror the reported regions a second time in right-to-left layouts.
            let regions = (proxy.reservedRegions(kind: .division, layoutDirectionBehavior: .fixed)
                + proxy.reservedRegions(kind: .occlusion, layoutDirectionBehavior: .fixed))
                .filter(\.isActive).map(\.frame)
            var candidates = [bounds]
            for region in regions {
                candidates = candidates.flatMap { candidate -> [CGRect] in
                    let obstruction = candidate.intersection(region)
                    guard !obstruction.isNull, !obstruction.isEmpty else { return [candidate] }
                    return [
                        CGRect(x: candidate.minX, y: candidate.minY, width: max(0, obstruction.minX - candidate.minX), height: candidate.height),
                        CGRect(x: obstruction.maxX, y: candidate.minY, width: max(0, candidate.maxX - obstruction.maxX), height: candidate.height),
                        CGRect(x: candidate.minX, y: candidate.minY, width: candidate.width, height: max(0, obstruction.minY - candidate.minY)),
                        CGRect(x: candidate.minX, y: obstruction.maxY, width: candidate.width, height: max(0, candidate.maxY - obstruction.maxY))
                    ].filter { $0.width >= 44 && $0.height >= 44 }
                }
            }
            // If no usable region fits a control, preserve the original layout rather than hiding it.
            return candidates.max { lhs, rhs in
                let a = lhs.width * lhs.height, b = rhs.width * rhs.height
                if a != b { return a < b }
                if lhs.midY != rhs.midY { return lhs.midY < rhs.midY }
                return lhs.midX < rhs.midX
            } ?? bounds
        }
        return bounds
    }
}
