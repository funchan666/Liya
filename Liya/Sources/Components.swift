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

struct LiyaFeedActionLabel: View {
    let title: String
    let count: String
    let icon: String
    var active = false

    var body: some View {
        HStack(spacing: 7) {
            Image(icon).resizable().scaledToFit().frame(width: 25, height: 25).accessibilityHidden(true)
            Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
            Text(count).font(.caption.weight(.medium)).monospacedDigit().foregroundStyle(.secondary)
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
            Text(LocalizedStringKey(title)).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white).frame(maxWidth: .infinity).frame(minHeight: 48)
                .background(liyaGradient.opacity(disabled ? 0.45 : 1), in: Capsule())
        }.buttonStyle(.plain).disabled(disabled)
    }
}

struct PageHeader: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var light = false
    var body: some View {
        DuoControlRegion { _ in
            HStack {
                Button(action: { dismiss() }) {
                    Image("back").renderingMode(light ? .template : .original).resizable().scaledToFit().foregroundStyle(.white).frame(width: 20, height: 20).frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel("Back")
                Spacer(minLength: 0)
                Text(LocalizedStringKey(title)).font(.headline).lineLimit(1).foregroundStyle(light ? .white : liyaInk)
                Spacer(minLength: 0)
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }.modifier(AdaptiveContainerMargins())
        }.frame(height: 44)
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
            Text(title).font(.headline).foregroundStyle(liyaInk)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(24)
    }
}

struct OfflineNote: View {
    let text: String
    var body: some View {
        Text(text).font(.footnote).foregroundStyle(liyaInk.opacity(0.8))
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
                        Text(LocalizedStringKey(title)).font(.title3.bold()).foregroundStyle(liyaInk)
                        Text(LocalizedStringKey(message)).multilineTextAlignment(.center).foregroundStyle(.secondary)
                        PrimaryButton(title: action, action: confirm)
                        Button("Cancel", action: cancel).font(.subheadline.bold()).foregroundStyle(liyaAccent).frame(minHeight: 44)
                    }.padding(24).frame(maxWidth: 440).frame(maxWidth: .infinity).frame(minHeight: size.height)
                }
            }
        }
    }
}

enum ConnectionNotice: String, Identifiable {
    case mutual, unavailable
    var id: String { rawValue }
}

struct ConnectionNoticeSheet: View {
    let notice: ConnectionNotice
    let dismiss: () -> Void
    var body: some View {
        ZStack {
            LiyaBackground()
            DuoControlRegion { size in
                ScrollView {
                    VStack(spacing: 15) {
                        Image(notice == .mutual ? "profile-action-follow" : "profile-action-message")
                            .resizable().scaledToFit().frame(width: 76, height: 76).accessibilityHidden(true)
                        Text(LocalizedStringKey(notice == .mutual ? "A connection starts with both of you" : "Please try again"))
                            .font(.title3.weight(.bold)).foregroundStyle(liyaInk).multilineTextAlignment(.center)
                        Text(LocalizedStringKey(notice == .mutual ? "Follow each other to send messages and enjoy voice or video calls." : "This action isn't available right now. Please try again later."))
                            .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        PrimaryButton(title: "Got it", action: dismiss)
                    }.padding(24).frame(maxWidth: 420).frame(maxWidth: .infinity).frame(minHeight: size.height)
                }
            }
        }
    }
}
