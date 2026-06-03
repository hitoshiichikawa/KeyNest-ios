import SwiftUI

/// Three-segment password-strength indicator.
///
/// SwiftUI port of `ui/widget/StrengthBar.kt`. Visual contract:
/// segments 14×4 pt with 2 pt gap, corner radius = height/2.
/// - `.strong`  → 3 filled with `KNColor.success`
/// - `.medium`  → 2 filled with `KNColor.warning`, last segment track
/// - `.weak`    → 1 filled with `KNColor.danger`, remaining segments track
/// - `nil` strength → caller should omit the view (Req 6.5: hide entirely
///   when the credential has no strength field). The Android parity is the
///   `View.GONE` default; SwiftUI's idiomatic equivalent is to not render.
struct StrengthBar: View {
    enum Strength: Equatable { case weak, medium, strong }

    let strength: Strength

    private static let segmentWidth: CGFloat = 14
    private static let segmentHeight: CGFloat = 4
    private static let gap: CGFloat = 2
    private static let segmentCount = 3

    var body: some View {
        HStack(spacing: Self.gap) {
            ForEach(0..<Self.segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: Self.segmentHeight / 2, style: .continuous)
                    .fill(color(at: index))
                    .frame(width: Self.segmentWidth, height: Self.segmentHeight)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private func color(at index: Int) -> Color {
        let filled: Int
        let fill: Color
        switch strength {
        case .weak:   filled = 1; fill = KNColor.danger
        case .medium: filled = 2; fill = KNColor.warning
        case .strong: filled = 3; fill = KNColor.success
        }
        return index < filled ? fill : KNColor.borderStrong
    }

    private var accessibilityLabel: String {
        switch strength {
        case .weak:   return "Password strength: weak"
        case .medium: return "Password strength: medium"
        case .strong: return "Password strength: strong"
        }
    }
}

#if DEBUG
#Preview {
    VStack(alignment: .leading, spacing: 16) {
        StrengthBar(strength: .weak)
        StrengthBar(strength: .medium)
        StrengthBar(strength: .strong)
    }
    .padding()
    .background(KNColor.bg)
}
#endif
