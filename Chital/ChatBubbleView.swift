import SwiftUI
import MarkdownUI
import Splash
import UserNotifications

struct ChatBubbleView: View {
    let message: ChatMessage
    let isThinking: Bool
    let onRetry: () -> Void
    
    @State private var isLoading = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme
    
    @ViewBuilder
    private func codeBlock(_ configuration: CodeBlockConfiguration) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(configuration.language?.isEmpty == false ? configuration.language! : "plain text")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .foregroundColor(Color(theme.plainTextColor))
                Spacer()
                Image(systemName: "doc.on.doc")
                    .onTapGesture {
                        copyToClipboard(configuration.content)
                    }
                    .opacity(isLoading ? 0 : 1)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            //            .background {
            //                Color(theme.backgroundColor)
            //            }
            
            Divider()
            
            ScrollView(.horizontal) {
                configuration.label
                    .relativeLineSpacing(.em(0.25))
                    .markdownTextStyle {
                        FontFamilyVariant(.monospaced)
                        FontSize(.em(0.85))
                    }
                    .padding()
            }
        }
        //                .background(Color.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .markdownMargin(top: .zero, bottom: .em(0.8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .padding(.vertical, 8)
    }
    
    private var theme: Splash.Theme {
        // NOTE: We are ignoring the Splash theme font
        switch self.colorScheme {
        case .dark:
            return .wwdc17(withFont: .init(size: 16))
        default:
            return .sunset(withFont: .init(size: 16))
        }
    }
    private func copyToClipboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
        
        withAnimation {
            isLoading = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation {
                isLoading = false
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(message.isUser ? "User" : "Assistant")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 2)
            }
            
            ZStack(alignment: .bottom) {
                if message.isUser {
                    Text(message.text != "" ? message.text : "...")
                        .padding(12)
                        .textSelection(.enabled)
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Markdown(message.text != "" ? message.text : "..." )
                        .padding(12)
                        .textSelection(.enabled)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .markdownBlockStyle(\.codeBlock) {
                            codeBlock($0)
                        }
                        .markdownCodeSyntaxHighlighter(.splash(theme: self.theme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                if (message.text != "") {
                    HStack() {
                        HStack() {
                            ChatBubbleButton(title: "Copy", systemImage: "doc.on.doc", action: copyText)
                            if shouldShowRetryButton {
                                ChatBubbleButton(title: "Retry", systemImage: "arrow.counterclockwise", action: onRetry)
                            }
                        }
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .padding(.trailing, -4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                        )
                        .offset(y: 0)
                        .opacity(isHovering ? 1 : 0)
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                        
                        Spacer()
                    }
                }
            }
        }
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var shouldShowRetryButton: Bool {
        return !message.isUser && !isThinking
    }
    
    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.text, forType: .string)
    }
}

struct ChatBubbleButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(PlainButtonStyle())
        .help(title)
        .font(.caption)
        .padding(.trailing, 4)
    }
}

#Preview {
    VStack(spacing: 20) {
        ChatBubbleView(
            message: ChatMessage(
                text: "Hello!",
                isUser: true,
                timestamp: Date()
            ),
            isThinking: false,
            onRetry: {}
        )
        
        ChatBubbleView(
            message: ChatMessage(
                text: "Hello! How can I assist you today?",
                isUser: false,
                timestamp: Date()
            ),
            isThinking: false,
            onRetry: {}
        )
    }
    .padding()
    .frame(width: 400)
}
