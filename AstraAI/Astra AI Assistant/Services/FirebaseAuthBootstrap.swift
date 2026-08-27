//
//  FirebaseAuthBootstrap.swift
//  AstraAssistant
//
//  Created by Alex on 11/8/26.
//

import Foundation
import FirebaseAuth
import Combine


@MainActor
final class FirebaseAuthBootstrap: ObservableObject {
    static let shared = FirebaseAuthBootstrap()

    @Published var isReady = false
    @Published var lastError: String?

    private init() {}

    func startAnonymousSessionIfNeeded() async {
        if Auth.auth().currentUser != nil {
            isReady = true
            return
        }

        do {
            _ = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<AuthDataResult, Error>) in
                Auth.auth().signInAnonymously { result, error in
                    if let error {
                        cont.resume(throwing: error)
                    } else if let result {
                        cont.resume(returning: result)
                    } else {
                        cont.resume(throwing: NSError(
                            domain: "FirebaseAuthBootstrap",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Anonymous sign-in returned no result."]
                        ))
                    }
                }
            }

            isReady = true
            lastError = nil
        } catch {
            isReady = false
            lastError = error.localizedDescription
        }
    }
}
