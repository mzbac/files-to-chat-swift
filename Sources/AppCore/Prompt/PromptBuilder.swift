public enum PromptBuilder {
    public static func makeContext(documentsText: String) -> String {
        return """
        You are a helpful assistant. Use ONLY the following documents to answer.

        ### DOCUMENTS
        \(documentsText)

        ### RULES
        - If the answer is not in the documents, say you don't know.
        - Keep answers concise unless asked for details.
        """
    }
}
