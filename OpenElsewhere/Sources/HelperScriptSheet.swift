import AppKit
import SwiftUI

/// The "Show me how" destination for the profile-helper setup task.
///
/// The handoff leaves this sheet undesigned; it is built from the same tokens
/// as the rest of the system. What it must carry is fixed: the three actions
/// that used to sit inline in `profileHelperCard` (Copy Script, Open Folder,
/// Check Again) plus the `chmod +x` line, arranged as the three steps the user
/// actually performs.
struct HelperScriptSheet: View {
    /// Written back so the setup strip can advance the moment the script lands.
    @Binding var isInstalled: Bool
    let onClose: () -> Void

    @State private var didCopy = false
    @State private var checkedAndMissing = false
    @Environment(\.colorScheme) private var scheme

    private var t: OETheme { OETheme.resolve(scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            OEHairline(theme: t)

            VStack(alignment: .leading, spacing: 12) {
                step(1,
                     title: "Copy the script",
                     detail: "It is four lines long and does one thing: run the browser you picked, with the profile flag.") {
                    Button(didCopy ? "Copied" : "Copy Script") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(ProfileRoutingHelper.scriptSource,
                                                       forType: .string)
                        withAnimation(OE.easeBase) { didCopy = true }
                    }
                    .buttonStyle(OESoftButtonStyle())
                }

                step(2,
                     title: "Save it as \(ProfileRoutingHelper.scriptName)",
                     detail: "In the folder that opens. Only you can write there — that restriction is what makes the folder a safe escape hatch from the sandbox.") {
                    Button("Open Folder") {
                        if let dir = ProfileRoutingHelper.scriptsDirectory {
                            NSWorkspace.shared.open(dir)
                        }
                    }
                    .buttonStyle(OESoftButtonStyle())
                }

                step(3,
                     title: "Make it executable",
                     detail: "In Terminal, from that folder:") {
                    EmptyView()
                }

                Text("chmod +x \(ProfileRoutingHelper.scriptName)")
                    .font(OEFont.code)
                    .foregroundStyle(t.textPrimary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .oeSurface(t.surfaceInset, border: t.borderInset, radius: OE.Radius.control)
                    .padding(.leading, 30)
            }

            if checkedAndMissing {
                Label("Not there yet — check the file name and that chmod ran.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(OEFont.rowSubtitle)
                    .foregroundStyle(t.warn)
                    .transition(.opacity)
            }

            OEHairline(theme: t)

            HStack(spacing: 8) {
                Spacer()
                Button("Check Again") {
                    let found = ProfileRoutingHelper.isInstalled
                    isInstalled = found
                    withAnimation(OE.easeBase) { checkedAndMissing = !found }
                    if found { onClose() }
                }
                .buttonStyle(OEChipButtonStyle())

                Button("Done") { onClose() }
                    .buttonStyle(OEFilledButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(OEBackground(theme: t))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: SetupTask.profileHelper.symbol)
                .font(.system(size: 15))
                .foregroundStyle(t.accent)
                .frame(width: 32, height: 32)
                .oeSurface(t.accentSoft, border: t.accentLine, radius: OE.Radius.chip)

            VStack(alignment: .leading, spacing: 2) {
                Text("Install the profile helper")
                    .font(OEFont.bannerTitle)
                    .foregroundStyle(t.textPrimary)
                Text("Three steps, once. Plain routing keeps working without it.")
                    .font(OEFont.bannerBody)
                    .foregroundStyle(t.textSecondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func step<Action: View>(_ number: Int,
                                    title: String,
                                    detail: String,
                                    @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(OEFont.button)
                .foregroundStyle(t.accent)
                .frame(width: 18, height: 18)
                .background(Circle().fill(t.accentSoft))
                .overlay(Circle().strokeBorder(t.accentLine, lineWidth: OE.hairline))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(OEFont.rowTitle)
                    .foregroundStyle(t.textPrimary)
                Text(detail)
                    .font(OEFont.rowSubtitle)
                    .foregroundStyle(t.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            action()
        }
    }
}
