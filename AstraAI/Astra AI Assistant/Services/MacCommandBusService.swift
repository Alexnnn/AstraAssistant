//
//  MacCommandBusService.swift
//  Astra AI Assistant
//
//  Created by Alex on 13/8/26.
//


import Foundation
import FirebaseFirestore

actor MacCommandBusService {
    static let shared = MacCommandBusService()

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var processing = Set<String>()
    private weak var executor: (any MacCommandExecuting)?
    private var uid: String = ""
    private var deviceId: String = ""

    private init() {}

    func start(
        uid: String,
        deviceId: String,
        executor: any MacCommandExecuting
    ) async {
        stop()

        self.uid = uid
        self.deviceId = deviceId
        self.executor = executor

        let ref = db.collection("users")
            .document(uid)
            .collection("commands")
            .whereField("targetDevice", isEqualTo: deviceId)
            .whereField("status", isEqualTo: CompanionCommandStatus.queued.rawValue)

        listener = ref.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                print("MacCommandBus listener error:", error.localizedDescription)
                return
            }
            guard let snapshot else { return }

            Task {
                await self.handleSnapshot(snapshot)
            }
        }

        print("MacCommandBus started for uid=\(uid), device=\(deviceId)")
    }

    func stop() {
        listener?.remove()
        listener = nil
        processing.removeAll()
    }

    // MARK: - Internal

    private func handleSnapshot(_ snapshot: QuerySnapshot) async {
        for change in snapshot.documentChanges {
            let doc = change.document
            let id = doc.documentID

            guard !processing.contains(id) else { continue }
            processing.insert(id)

            Task {
                await self.processDocument(doc)
                await self.finishProcessing(id: id)
            }
        }
    }

    private func finishProcessing(id: String) {
        processing.remove(id)
    }

    private func processDocument(_ doc: QueryDocumentSnapshot) async {
        do {
            let claimed = try await claimCommand(docID: doc.documentID)
            guard claimed else { return }

            guard let request = parseCommand(doc: doc) else {
                try await markError(docID: doc.documentID, message: "Invalid command payload.")
                return
            }

            guard let executor else {
                try await markError(docID: doc.documentID, message: "Executor not configured.")
                return
            }

            let result = try await executor.execute(request)

            try await markDone(
                docID: doc.documentID,
                result: result.data
            )

        } catch {
            let msg = (error as NSError).localizedDescription
            try? await markError(docID: doc.documentID, message: msg)
        }
    }

    private func parseCommand(doc: QueryDocumentSnapshot) -> CompanionCommandRequest? {
        let data = doc.data()

        guard
            let typeRaw = data["type"] as? String,
            let type = CompanionCommandType(rawValue: typeRaw),
            let sourceDevice = data["sourceDevice"] as? String,
            let targetDevice = data["targetDevice"] as? String
        else {
            return nil
        }

        let payload = data["payload"] as? [String: Any] ?? [:]

        return CompanionCommandRequest(
            id: doc.documentID,
            uid: uid,
            sourceDevice: sourceDevice,
            targetDevice: targetDevice,
            type: type,
            payload: payload
        )
    }

    private func claimCommand(docID: String) async throws -> Bool {
        let ref = db.collection("users").document(uid).collection("commands").document(docID)

        return try await withCheckedThrowingContinuation { cont in
            db.runTransaction({ transaction, errorPointer in
                do {
                    let snap = try transaction.getDocument(ref)
                    let status = (snap.data()?["status"] as? String) ?? ""

                    guard status == CompanionCommandStatus.queued.rawValue else {
                        return false as NSNumber
                    }

                    transaction.updateData([
                        "status": CompanionCommandStatus.running.rawValue,
                        "claimedBy": self.deviceId,
                        "startedAt": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ], forDocument: ref)

                    return true as NSNumber
                } catch let e {
                    errorPointer?.pointee = e as NSError
                    return false as NSNumber
                }
            }) { obj, err in
                if let err {
                    cont.resume(throwing: err)
                    return
                }
                let ok = (obj as? NSNumber)?.boolValue ?? false
                cont.resume(returning: ok)
            }
        }
    }

    private func markDone(docID: String, result: [String: Any]) async throws {
        let cmdRef = db.collection("users").document(uid).collection("commands").document(docID)
        let respRef = db.collection("users").document(uid).collection("responses").document(docID)

        try await cmdRef.setData([
            "status": CompanionCommandStatus.done.rawValue,
            "result": result,
            "finishedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp(),
            "errorMessage": FieldValue.delete()
        ], merge: true)

        try await respRef.setData([
            "commandId": docID,
            "status": CompanionCommandStatus.done.rawValue,
            "data": result,
            "createdAt": FieldValue.serverTimestamp(),
            "deviceId": deviceId
        ], merge: true)
    }

    private func markError(docID: String, message: String) async throws {
        let cmdRef = db.collection("users").document(uid).collection("commands").document(docID)
        let respRef = db.collection("users").document(uid).collection("responses").document(docID)

        try await cmdRef.setData([
            "status": CompanionCommandStatus.error.rawValue,
            "errorMessage": message,
            "finishedAt": FieldValue.serverTimestamp(),
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)

        try await respRef.setData([
            "commandId": docID,
            "status": CompanionCommandStatus.error.rawValue,
            "error": message,
            "createdAt": FieldValue.serverTimestamp(),
            "deviceId": deviceId
        ], merge: true)
    }
}
