import SwiftUI

extension View {
    @ViewBuilder
    func onLiyaChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        if #available(iOS 17, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }
}

let liyaInk = Color(red: 0.13, green: 0.13, blue: 0.23)
let liyaAccent = Color(red: 0.44, green: 0.22, blue: 0.95)
let liyaGradient = LinearGradient(colors: [Color(red: 0.05, green: 0.52, blue: 0.99), Color(red: 0.64, green: 0.14, blue: 0.96)], startPoint: .leading, endPoint: .trailing)

enum LiyaType {
    enum Weight: String {
        case regular = "Nunito-Regular"
        case medium = "Nunito-Medium"
        case semibold = "Nunito-SemiBold"
        case bold = "Nunito-Bold"
    }

    static func text(_ style: Font.TextStyle, weight: Weight? = nil) -> Font {
        let points: CGFloat
        switch style {
        case .largeTitle: points = 34
        case .title: points = 28
        case .title2: points = 22
        case .title3: points = 20
        case .callout: points = 16
        case .subheadline: points = 15
        case .footnote: points = 13
        case .caption: points = 12
        case .caption2: points = 11
        default: points = 17
        }
        let face = weight ?? (style == .headline ? .semibold : .regular)
        return .custom(face.rawValue, size: points, relativeTo: style)
    }

    static let reading = text(.body)
    static let detail = text(.subheadline)
    static let action = Font.custom("Nunito-Bold", size: 16, relativeTo: .headline)
    static let sectionHeading = Font.custom("Nunito-Bold", size: 18, relativeTo: .headline)
    static let journalTitle = Font.custom("InstrumentSerif-Regular", size: 32, relativeTo: .title)
}

struct LiyaFeedActionLabel: View {
    let title: String
    let count: String
    let icon: String
    var active = false

    var body: some View {
        HStack(spacing: 7) {
            Image(icon).resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
            Text(LocalizedStringKey(title)).font(LiyaType.text(.caption, weight: .semibold)).lineLimit(1)
            Text(verbatim: count).font(LiyaType.text(.subheadline, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(active ? liyaAccent : liyaInk)
        .padding(.horizontal, 12).frame(minHeight: 44)
        .background(Color(red: 0.96, green: 0.95, blue: 0.99), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct LiyaFeedCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(14)
            .background(.white.opacity(0.90), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(liyaAccent.opacity(0.08), lineWidth: 1))
    }
}

struct LiyaLoadingIndicator: View {
    var size: CGFloat = 34
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotating = false

    var body: some View {
        Image("liya-spinner")
            .resizable().scaledToFit().frame(width: size, height: size)
            .rotationEffect(.degrees(rotating ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1.1).repeatForever(autoreverses: false), value: rotating)
            .onAppear { rotating = !reduceMotion }
            .accessibilityLabel("Loading")
    }
}

struct LiyaBackground: View {
    var name = "plain-background"
    var body: some View {
        GeometryReader { geometry in
            Image(name).resizable().aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

struct PrimaryButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title)).font(LiyaType.action)
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 48)
                .background(liyaGradient.opacity(disabled ? 0.45 : 1), in: Capsule())
        }.buttonStyle(.plain).disabled(disabled)
    }
}

struct PageHeader: View {
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .headline) private var headerHeight: CGFloat = 44
    let title: String
    let light: Bool

    init(title: String, light: Bool = false) {
        self.title = title
        self.light = light
    }

    var body: some View {
        DuoControlRegion { _ in
            HStack {
                Button(action: { dismiss() }) {
                    Image("back").renderingMode(light ? .template : .original).resizable().scaledToFit().foregroundStyle(.white).frame(width: 20, height: 20).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Back")
                Spacer(minLength: 0)
                Text(LocalizedStringKey(title)).font(LiyaType.sectionHeading)
                    .lineLimit(2).multilineTextAlignment(.center).foregroundStyle(light ? .white : liyaInk)
                Spacer(minLength: 0)
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }.modifier(AdaptiveContainerMargins())
        }.frame(height: max(44, headerHeight))
    }
}

struct AdaptiveContainerMargins: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.contentMargins(for: .container, edges: .horizontal)
        } else {
            content
        }
    }
}

struct EmptyState: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image("empty-art").resizable().scaledToFit().frame(width: 78, height: 72).accessibilityHidden(true)
            Text(LocalizedStringKey(title)).font(LiyaType.sectionHeading).foregroundStyle(liyaInk).multilineTextAlignment(.center)
            if !detail.isEmpty { Text(LocalizedStringKey(detail)).font(LiyaType.detail).foregroundStyle(.secondary).multilineTextAlignment(.center) }
        }.frame(maxWidth: .infinity).padding(24)
    }
}

struct OfflineNote: View {
    let text: String
    var body: some View {
        Text(text).font(LiyaType.text(.footnote)).foregroundStyle(liyaInk.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct PageShell<Content: View>: View {
    @Environment(\.liyaTabBarClearance) private var tabBarClearance
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        ZStack {
            LiyaBackground()
            VStack(spacing: 0) {
                PageHeader(title: title)
                ScrollView { content.frame(maxWidth: 620).frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.bottom, 30 + tabBarClearance) }
            }
        }.navigationBarHidden(true)
    }
}


struct LocalConfirmation: View {
    let title: String
    let message: String
    let action: String
    let confirm: () -> Void
    let cancel: () -> Void
    var body: some View {
        ZStack {
            LiyaBackground()
            DuoControlRegion { size in
                ScrollView {
                    VStack(spacing: 18) {
                        Text(LocalizedStringKey(title)).font(LiyaType.text(.title3, weight: .bold)).foregroundStyle(liyaInk)
                        Text(LocalizedStringKey(message)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        PrimaryButton(title: action, action: confirm)
                        Button("Cancel", action: cancel).font(LiyaType.text(.subheadline, weight: .bold)).foregroundStyle(liyaAccent).frame(minHeight: 44)
                    }.padding(24).frame(maxWidth: 440).frame(maxWidth: .infinity).frame(minHeight: size.height)
                }
            }
        }
    }
}

private let safetyRose = Color(red: 0.59, green: 0.16, blue: 0.25)
private let safetyIndigo = Color(red: 0.24, green: 0.19, blue: 0.44)

private struct SafetyPanelHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct SafetyPanel<Avatar: View, Content: View>: View {
    let title: String
    let subject: String?
    let back: (() -> Void)?
    let close: () -> Void
    let busy: Bool
    let avatar: Avatar
    let content: Content
    @State private var measuredHeight: CGFloat = 228
    @Environment(\.layoutDirection) private var layoutDirection

    init(title: String, subject: String?, back: (() -> Void)?, close: @escaping () -> Void,
         busy: Bool = false, @ViewBuilder avatar: () -> Avatar, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subject = subject
        self.back = back
        self.close = close
        self.busy = busy
        self.avatar = avatar()
        self.content = content()
    }

    var body: some View {
        DuoControlRegion { _ in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 11) {
                        if let back {
                            Button(action: back) {
                                Image("back").renderingMode(.template).resizable().scaledToFit()
                                    .frame(width: 18, height: 18)
                                    .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .foregroundStyle(liyaInk).accessibilityLabel("Back").disabled(busy)
                        } else {
                            avatar.frame(width: 46, height: 46).clipShape(Circle()).accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(LocalizedStringKey(title))
                                .font(LiyaType.text(.title3, weight: .bold))
                                .foregroundStyle(liyaInk).accessibilityAddTraits(.isHeader)
                            if let subject, !subject.isEmpty {
                                Text(verbatim: subject).font(LiyaType.detail).foregroundStyle(liyaInk.opacity(0.72))
                            }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: close) {
                            Image("close").renderingMode(.template).resizable().scaledToFit()
                                .frame(width: 26, height: 26).frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .foregroundStyle(liyaInk.opacity(0.62)).accessibilityLabel("Close").disabled(busy)
                    }
                    .buttonStyle(.plain)
                    Divider().accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) { content }
                }
                .frame(maxWidth: 480).frame(maxWidth: .infinity)
                .padding(.horizontal, 20).padding(.top, 25).padding(.bottom, 12)
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: SafetyPanelHeight.self, value: ceil(proxy.size.height))
                })
            }
        }
        .background(Color(red: 0.996, green: 0.990, blue: 0.998).ignoresSafeArea())
        .preferredColorScheme(.light)
        .onPreferenceChange(SafetyPanelHeight.self) { height in
            if height > 0, abs(measuredHeight - height) >= 1 { measuredHeight = height }
        }
        .presentationDetents([.height(measuredHeight)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
        .accessibilityAction(.escape) { if !busy { close() } }
    }
}

struct SafetyActionRow: View {
    enum Kind { case report, block, unblock, edit }
    let title: String
    let kind: Kind
    let action: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    private var artwork: String {
        switch kind {
        case .report: return "safety-report"
        case .block: return "safety-block"
        case .unblock: return "profile-action-follow"
        case .edit: return "profile-home-edit"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(artwork).resizable().scaledToFit().frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                Text(LocalizedStringKey(title)).font(LiyaType.text(.body, weight: .semibold))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image("back").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 13, height: 13)
                    .scaleEffect(x: layoutDirection == .rightToLeft ? 1 : -1, y: 1)
                    .foregroundStyle(liyaInk.opacity(0.45)).accessibilityHidden(true)
            }
            .foregroundStyle(kind == .block ? safetyRose : liyaInk)
            .padding(.horizontal, 3).padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 54).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct SafetyReasonList: View {
    let selected: String?
    let choose: (String) -> Void
    private let reasons = ["Sexual content", "Harassment", "Discrimination", "Incorrect content", "Other"]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(reasons, id: \.self) { reason in
                Button { choose(reason) } label: {
                    HStack(spacing: 12) {
                        Text(LocalizedStringKey(reason)).font(LiyaType.reading)
                            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                        if selected == reason {
                            Image("consent-on").resizable().scaledToFit().frame(width: 21, height: 21)
                                .accessibilityHidden(true)
                        } else {
                            Image("consent-off").renderingMode(.template).resizable().scaledToFit()
                                .frame(width: 21, height: 21).foregroundStyle(liyaInk.opacity(0.38))
                                .accessibilityHidden(true)
                        }
                    }
                    .foregroundStyle(liyaInk).padding(.horizontal, 14).padding(.vertical, 6)
                    .frame(minHeight: 46).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == reason ? .isSelected : [])
                if reason != reasons.last { Divider().padding(.horizontal, 14).accessibilityHidden(true) }
            }
        }
        .background(safetyIndigo.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SafetySubmitButton: View {
    let title: String
    var destructive = false
    var busy = false
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if busy { LiyaLoadingIndicator(size: 21).accessibilityHidden(true) }
                Text(LocalizedStringKey(title)).font(LiyaType.text(.headline)).multilineTextAlignment(.center)
            }
            .foregroundStyle(disabled && !busy ? liyaInk.opacity(0.67) : .white)
            .padding(.vertical, 10).padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 48)
            .background(disabled && !busy ? Color(red: 0.93, green: 0.92, blue: 0.95) :
                            (destructive ? safetyRose : safetyIndigo), in: RoundedRectangle(cornerRadius: 15))
        }
        .buttonStyle(.plain).disabled(disabled || busy)
    }
}

struct SafetySecondaryButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(title)).font(LiyaType.text(.subheadline, weight: .semibold))
                .foregroundStyle(isEnabled ? safetyIndigo : liyaInk.opacity(0.55))
                .multilineTextAlignment(.center).padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(safetyIndigo.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
}
