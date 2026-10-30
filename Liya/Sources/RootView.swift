import SwiftUI

private enum LiyaTab: Int, CaseIterable {
    case discover, square, compose, messages, profile
    var title: String {
        switch self { case .discover: return "Video"; case .square: return "Square"; case .compose: return "Create"; case .messages: return "Messages"; case .profile: return "Profile" }
    }
    func image(selected: Bool) -> String {
        switch self {
        case .discover: return selected ? "tab-square" : "tab-video-inactive"
        case .square: return selected ? "tab-discover" : "tab-square-inactive"
        case .compose: return "tab-create"
        case .messages: return selected ? "tab-message" : "tab-message-inactive"
        case .profile: return selected ? "tab-profile" : "tab-profile-inactive"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: LocalStore
    @State private var selection: LiyaTab = .discover

    var body: some View {
        if !store.inPreview {
            WelcomeView { store.inPreview = true }
        } else {
            ZStack {
                Group {
                    tab(.discover) { VideoHome(active: selection == .discover) }
                    tab(.square) { SquareHome() }
                    tab(.compose) { ComposeHome() }
                    tab(.messages) { MessagesHome() }
                    tab(.profile) { ProfileHome() }
                }
            }
            .onChange(of: store.videoRequest) { request in
                if request != nil { selection = .discover }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DuoControlRegion { size in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(LiyaTab.allCases, id: \.rawValue) { item in
                                Button { selection = item } label: {
                                    VStack(spacing: 3) {
                                        Image(item.image(selected: selection == item)).resizable().scaledToFit().frame(width: item == .compose ? 34 : 24, height: 34)
                                        Text(item.title).font(.system(size: 10, weight: selection == item ? .bold : .regular))
                                            .foregroundStyle(selection == item ? liyaAccent : .secondary)
                                    }.frame(width: max(52, (size.width - 16) / CGFloat(LiyaTab.allCases.count)), height: 52).contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityLabel(item.title).accessibilityAddTraits(selection == item ? .isSelected : [])
                            }
                        }.padding(.horizontal, 8).modifier(AdaptiveContainerMargins())
                    }
                }.frame(height: 52).background(.white)
            }
        }
    }

    private func tab<Content: View>(_ item: LiyaTab, @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { content() }
            .opacity(selection == item ? 1 : 0)
            .allowsHitTesting(selection == item)
            .accessibilityHidden(selection != item)
    }
}

private struct WelcomeView: View {
    let enter: () -> Void
    @State private var policy: PolicyPage?
    var body: some View {
        ZStack {
            LiyaBackground(name: "color-background")
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 22) {
                        Spacer(minLength: 50)
                        Image("app-mark").resizable().scaledToFit().frame(width: 150, height: 150).clipShape(RoundedRectangle(cornerRadius: 30)).accessibilityHidden(true)
                        Text("Liya").font(.system(size: 38, weight: .bold)).foregroundStyle(.white)
                        Text("A little space for how you feel.").font(.headline).foregroundStyle(.white).multilineTextAlignment(.center)
                        Spacer(minLength: 100)
                        Button(action: enter) {
                            Text("Explore on this device").fontWeight(.semibold).foregroundStyle(liyaInk).frame(maxWidth: .infinity).frame(minHeight: 50).background(.white, in: Capsule())
                        }.buttonStyle(.plain)
                        Text("Local preview · Sign-in and online features are not connected yet.")
                            .font(.footnote).foregroundStyle(.white).multilineTextAlignment(.center)
                        HStack {
                            Button("Terms of Service") { policy = .terms }
                            Text("·")
                            Button("Privacy Policy") { policy = .privacy }
                        }.font(.footnote).foregroundStyle(.white)
                    }.padding(.horizontal, 32).padding(.vertical, 32).frame(minHeight: geometry.size.height)
                }
            }
        }.sheet(item: $policy) { page in
            NavigationStack {
                InformationView(title: page == .terms ? "Terms of Service" : "Privacy Policy", message: "This policy has not been published yet.")
            }
        }
    }
}

private enum PolicyPage: String, Identifiable {
    case terms, privacy
    var id: String { rawValue }
}
