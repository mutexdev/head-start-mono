// ios/Headstart/Core/FirestoreStreams.swift
//
// Decision D8 — repositories expose `AsyncStream` and nothing else. One streaming
// primitive throughout: this codebase contains no reactive-framework publishers, no
// subjects and no subscription closures, and it must stay that way. (The literal names are
// left out on purpose — the done-criteria grep for them must come back empty, and a
// comment quoting them would be the only hit.)
//
// A Firestore snapshot listener becomes an `AsyncStream` whose `onTermination` removes the
// registration, so cancelling the consuming `Task` detaches the listener. Consumers are
// `@MainActor` repositories, so the non-Sendable snapshot types never cross an isolation
// boundary; the one escape hatch is the `ListenerBox` below.

import Foundation
import FirebaseFirestore

/// `ListenerRegistration` is a non-Sendable class, but the only thing the termination
/// handler does with it is call `remove()`, which the SDK documents as safe to call from
/// any thread. The box hands exactly that one capability across the boundary, and nothing
/// else. This is the ONLY `@unchecked Sendable` in the app (see the concurrency law at the
/// top of BackendEnvironment.swift).
private final class ListenerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var registration: ListenerRegistration?
    private var stopped = false

    /// Attaches, or immediately detaches if `stop()` already won the race — an
    /// `AsyncStream` whose consumer is cancelled before the listener is installed would
    /// otherwise leak the registration forever.
    func attach(_ registration: ListenerRegistration) {
        lock.lock()
        defer { lock.unlock() }
        if stopped {
            registration.remove()
        } else {
            self.registration = registration
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        stopped = true
        registration?.remove()
        registration = nil
    }
}

public extension Query {

    /// Live query results, newest snapshot first-to-last as Firestore delivers them.
    ///
    /// Errors (offline, a transient permission blip) are logged and the stream stays open:
    /// Firestore retries on its own and the next snapshot resumes delivery. A stream that
    /// finished on the first error would leave a screen permanently blank.
    func documentsStream() -> AsyncStream<[QueryDocumentSnapshot]> {
        AsyncStream { continuation in
            let box = ListenerBox()
            continuation.onTermination = { _ in box.stop() }
            box.attach(addSnapshotListener { snapshot, error in
                if let error {
                    NSLog("[HS][fs] query listener error: \(error.localizedDescription)")
                    return
                }
                continuation.yield(snapshot?.documents ?? [])
            })
        }
    }

    /// The same stream, already mapped through a document mapper, so a repository never has
    /// to hold a non-Sendable snapshot. Documents the mapper rejects are dropped.
    func modelsStream<T: Sendable>(
        _ transform: @escaping @Sendable (String, [String: Any]) -> T?
    ) -> AsyncStream<[T]> {
        AsyncStream { continuation in
            let box = ListenerBox()
            continuation.onTermination = { _ in box.stop() }
            box.attach(addSnapshotListener { snapshot, error in
                if let error {
                    NSLog("[HS][fs] query listener error: \(error.localizedDescription)")
                    return
                }
                let models = (snapshot?.documents ?? []).compactMap { transform($0.documentID, $0.data()) }
                continuation.yield(models)
            })
        }
    }
}

public extension DocumentReference {

    /// Live document snapshots. Yields nil when the document does not exist.
    func snapshotStream() -> AsyncStream<DocumentSnapshot?> {
        AsyncStream { continuation in
            let box = ListenerBox()
            continuation.onTermination = { _ in box.stop() }
            box.attach(addSnapshotListener { snapshot, error in
                if let error {
                    NSLog("[HS][fs] document listener error: \(error.localizedDescription)")
                    return
                }
                continuation.yield(snapshot)
            })
        }
    }

    /// The mapped variant: yields nil while the document is missing or unmappable.
    func modelStream<T: Sendable>(
        _ transform: @escaping @Sendable (String, [String: Any]) -> T?
    ) -> AsyncStream<T?> {
        AsyncStream { continuation in
            let box = ListenerBox()
            continuation.onTermination = { _ in box.stop() }
            box.attach(addSnapshotListener { snapshot, error in
                if let error {
                    NSLog("[HS][fs] document listener error: \(error.localizedDescription)")
                    return
                }
                guard let data = snapshot?.data(), let id = snapshot?.documentID else {
                    continuation.yield(nil)
                    return
                }
                continuation.yield(transform(id, data))
            })
        }
    }
}
