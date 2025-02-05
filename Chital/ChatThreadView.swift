import SwiftUI
import SwiftData

struct ChatThreadView: View {
    @AppStorage("titleSummaryPrompt") private var titleSummaryPrompt = AppConstants.titleSummaryPrompt
    @AppStorage("defaultModelName") private var defaultModelName = AppConstants.defaultModelName
    
    @Environment(\.modelContext) private var context
    @Bindable var thread: ChatThread
    @Binding var isDraft: Bool
    
    @FocusState private var isTextFieldFocused: Bool
    @State private var currentInputMessage: String = ""
    
    @State private var errorMessage: String?
    @State private var shouldShowErrorAlert = false
    
    @State private var scrollProxy: ScrollViewProxy?
    
    let availableModels: [String]
    
    var body: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(chronologicalMessages) { message in
                            ChatBubbleView(message: message, isThinking: thread.isThinking) {
                                retry(message)
                            }
                            .id(message.id)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: .infinity)
                .onChange(of: thread.messages.count) { oldValue, newValue in
                    scrollToBottom(proxy: proxy)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToBottom(proxy: proxy)
                }
            }
            
            ChatInputView(
                currentInputMessage: $currentInputMessage,
                isTextFieldFocused: _isTextFieldFocused,
                isThinking: thread.isThinking,
                onSubmit: insertChatMessage,
                selectedModel: Binding(
                    get: { thread.selectedModel ?? "" },
                    set: { thread.selectedModel = $0 }
                ),
                modelOptions: availableModels
            )
        }
        .padding()
        .onAppear {
            focusTextField()
            ensureModelSelected()
        }
        .onChange(of: thread.id) { _, _ in
            focusTextField()
        }
        .alert("Error", isPresented: $shouldShowErrorAlert, actions: {
            Button("OK") {
                errorMessage = nil
            }
        }, message: {
            Text(errorMessage ?? "An unknown error occurred.")
        })
    }
    
    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let lastMessage = chronologicalMessages.last {
            withAnimation {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
            }
        }
    }
    
    private func focusTextField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isTextFieldFocused = true
        }
    }
    
    private func ensureModelSelected() {
        if thread.selectedModel == nil || !availableModels.contains(thread.selectedModel!) {
            thread.selectedModel = defaultModelName == "" ? availableModels.first : defaultModelName
        }
    }
    
    private func sendMessageStream() {
        if isDraft {
            convertDraftToRegularThread()
        }
        
        currentInputMessage = ""
        thread.isThinking = true
        
        Task {
            do {
                ensureModelSelected()
                guard let selectedModel = thread.selectedModel, !selectedModel.isEmpty else {
                    throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
                }
                
                let ollamaService = OllamaService()
                let ollamaMessages = chronologicalMessages.map { OllamaChatMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }
                let stream = ollamaService.streamConversation(model: selectedModel, messages: ollamaMessages)
                let assistantMessage = ChatMessage(text: "", isUser: false, timestamp: Date())
                
                await MainActor.run {
                    thread.messages.append(assistantMessage)
                    context.insert(assistantMessage)
                }
                
                for try await partialResponse in stream {
                    await MainActor.run {
                        assistantMessage.text += partialResponse
                        scrollProxy?.scrollTo(assistantMessage.id, anchor: .bottom)
                    }
                }
                
                await MainActor.run {
                    thread.isThinking = false
                    if !thread.hasReceivedFirstMessage {
                        thread.hasReceivedFirstMessage = true
                        setThreadTitle()
                    }
                    focusTextField()
                }
            } catch {
                await handleError(error)
            }
        }
    }
    
    private func convertDraftToRegularThread() {
        isDraft = false
        thread.createdAt = Date()
        context.insert(thread)
    }
    
    private func insertChatMessage() {
        if currentInputMessage.isEmpty {
            return
        }
        
        let newMessage = ChatMessage(text: currentInputMessage, isUser: true, timestamp: Date())
        thread.messages.append(newMessage)
        context.insert(newMessage)
        
        sendMessageStream()
    }
    
    private func retry(_ message: ChatMessage) {
        guard let index = chronologicalMessages.firstIndex(where: { $0.id == message.id }) else {
            return
        }
        
        let messagesToRemove = Array(chronologicalMessages[index...])
        for messageToRemove in messagesToRemove {
            if let messageIndex = thread.messages.firstIndex(where: { $0.id == messageToRemove.id }) {
                thread.messages.remove(at: messageIndex)
                context.delete(messageToRemove)
            }
        }
        
        sendMessageStream()
    }
    
    private func handleError(_ error: Error) async {
        await MainActor.run {
            shouldShowErrorAlert = true
            thread.isThinking = false
            
            let networkError = error as? URLError
            let defaultErrorMessage = "An unexpected error occurred while communicating with the Ollama API: \(error.localizedDescription)"
            
            if networkError == nil {
                errorMessage = defaultErrorMessage
            } else {
                switch networkError?.code {
                case .cannotConnectToHost:
                    errorMessage = "Unable to connect to the Ollama API. Please ensure that the Ollama server is running."
                case .timedOut:
                    errorMessage = "The request to Ollama API timed out. Please try again later."
                default:
                    errorMessage = defaultErrorMessage
                }
            }
        }
    }
    
    private func setThreadTitle() {
        Task {
            do {
                guard let selectedModel = thread.selectedModel, !selectedModel.isEmpty else {
                    throw NSError(domain: "ChatView", code: 1, userInfo: [NSLocalizedDescriptionKey: "No model selected"])
                }
                
                var ollamaMessages = chronologicalMessages.map { OllamaChatMessage(role: $0.isUser ? "user" : "assistant", content: $0.text) }
                ollamaMessages.append(OllamaChatMessage(role: "user", content: titleSummaryPrompt))
                
                let ollamaService = OllamaService()
                var summaryResponse = try await ollamaService.sendSingleMessage(model: selectedModel, messages: ollamaMessages)
                
                let thinkModels = ["deepseek-r1:8b","deepseek-r1:latest"]
                
                if thinkModels.contains(selectedModel) {
                    let pattern = "<think>.*?</think>"
                    
                    if let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators) {
                        let range = NSRange(location: 0, length: summaryResponse.utf16.count)
                        summaryResponse = regex.stringByReplacingMatches(in: summaryResponse, options: [], range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                
                await MainActor.run {
                    setThreadTitle(summaryResponse)
                }
            } catch {
                print("Error summarizing thread: \(error.localizedDescription)")
            }
        }
    }
    
    private func setThreadTitle(_ summary: String) {
        thread.title = summary
        context.insert(thread)
    }
    
    private var chronologicalMessages: [ChatMessage] {
        thread.messages.sorted { $0.createdAt < $1.createdAt }
    }
}
