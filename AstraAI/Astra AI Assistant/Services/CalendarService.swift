//
//  CalendarService.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation
import EventKit

@MainActor
final class CalendarService {
    static let shared = CalendarService()
    private init() {}

    private func makeStore() -> EKEventStore {
        EKEventStore()
    }

    func requestAccessIfNeeded() async throws -> Bool {
        let store = makeStore()
        return try await withCheckedThrowingContinuation { cont in
            store.requestAccess(to: .event) { granted, error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume(returning: granted) }
            }
        }
    }

    func eventsForToday(limit: Int = 10) async throws -> [EKEvent] {
        let store = makeStore()
        let granted: Bool = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: granted)
                }
            }
        }

        guard granted else {
            throw NSError(domain: "CalendarService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Calendar access denied."
            ])
        }

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start)!

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(limit)
            .map { $0 }
    }

    func addEvent(title: String, start: Date, end: Date, notes: String? = nil) async throws {
        let store = makeStore()
        let granted: Bool = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            store.requestAccess(to: .event) { granted, error in
                if let error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume(returning: granted)
                }
            }
        }

        guard granted else {
            throw NSError(domain: "CalendarService", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Calendar access denied."
            ])
        }

        guard let calendar = store.defaultCalendarForNewEvents else {
            throw NSError(domain: "CalendarService", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "No default calendar found."
            ])
        }

        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.calendar = calendar
        event.notes = notes

        try store.save(event, span: .thisEvent)
    }
}
