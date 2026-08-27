//
//  ConversationCloudMirrorService.swift
//  Astra AI Assistant
//
//  Created by Alex on 13/8/26.
//

import Foundation
import FirebaseFirestore

actor ConversationCloudMirrorService {
    static let shared = ConversationCloudMirrorService()

    private let db = Firestore.firestore()

    private init() {}

    func syncConversation(uid: String, conversationId: UUID) async {
        let convId = conversationId.uuidString

        let summaries = ConversationStore.shared.listConversations()
        guard let summary = summaries.first(where: { $0.id == conversationId }) else {
            // conversation deleted
            let convRef = db.collection("users").document(uid)
                .collection("remoteConversations").document(convId)
            try? await convRef.delete()
            return
        }

        let messages = ConversationStore.shared.loadMessages(conversationId: conversationId)

        let convRef = db.collection("users").document(uid)
            .collection("remoteConversations").document(convId)

        let lastMessage = messages.last?.content ?? ""

        try? await convRef.setData([
            "conversationId": convId,
            "title": summary.title,
            "lastMessage": lastMessage,
            "updatedAt": FieldValue.serverTimestamp(),
            "source": "mac-local-sync"
        ], merge: true)

        for m in messages {
            let msgRef = convRef.collection("messages").document(m.id.uuidString)
            try? await msgRef.setData([
                "role": m.role.rawValue,
                "text": m.content,
                "createdAt": Timestamp(date: m.createdAt)
            ], merge: true)
        }
    }

    func fullBackfill(uid: String) async {
        let conversations = ConversationStore.shared.listConversations()
        for c in conversations {
            await syncConversation(uid: uid, conversationId: c.id)
        }
    }
}
