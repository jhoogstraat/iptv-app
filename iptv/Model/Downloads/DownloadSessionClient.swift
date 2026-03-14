//
//  DownloadSessionClient.swift
//  iptv
//
//  Created by Codex on 11.03.26.
//

import Foundation

final class DownloadSessionClient: NSObject, @unchecked Sendable {
    enum Event: Sendable {
        case progress(taskIdentifier: Int, bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpected: Int64)
        case finished(taskIdentifier: Int, temporaryURL: URL)
        case failed(taskIdentifier: Int, errorDomain: String, errorCode: Int, description: String, resumeData: Data?)
    }

    let events: AsyncStream<Event>

    private let identifier: String
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: AsyncStream<Event>.Continuation?
    nonisolated(unsafe) private var tasksByIdentifier: [Int: URLSessionDownloadTask] = [:]
    nonisolated(unsafe) private var session: URLSession!

    init(identifier: String = "com.jhoogstraat.iptv.downloads") {
        self.identifier = identifier
        var capturedContinuation: AsyncStream<Event>.Continuation?
        self.events = AsyncStream<Event> { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
        super.init()
        self.session = makeSession()
    }

    nonisolated func startDownload(from url: URL) -> Int {
        let task = session.downloadTask(with: url)
        store(task: task)
        task.resume()
        return task.taskIdentifier
    }

    nonisolated func resumeDownload(with resumeData: Data) -> Int {
        let task = session.downloadTask(withResumeData: resumeData)
        store(task: task)
        task.resume()
        return task.taskIdentifier
    }

    nonisolated func cancel(taskIdentifier: Int) {
        guard let task = task(for: taskIdentifier) else { return }
        removeTask(withIdentifier: taskIdentifier)
        task.cancel()
    }

    nonisolated func pause(taskIdentifier: Int) async -> Data? {
        guard let task = task(for: taskIdentifier) else { return nil }
        return await withCheckedContinuation { continuation in
            task.cancel { [weak self] resumeData in
                self?.removeTask(withIdentifier: taskIdentifier)
                continuation.resume(returning: resumeData)
            }
        }
    }

    nonisolated private func makeSession() -> URLSession {
        let configuration: URLSessionConfiguration
        // macOS builds in this project do not ship the application-identifier entitlement
        // required for background URLSession adoption, so use a foreground session there.
        #if os(iOS)
        configuration = .background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        configuration.waitsForConnectivity = true
        #else
        configuration = .default
        #endif
        configuration.allowsCellularAccess = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60 * 24
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    nonisolated private func store(task: URLSessionDownloadTask) {
        lock.lock()
        tasksByIdentifier[task.taskIdentifier] = task
        lock.unlock()
    }

    nonisolated private func task(for identifier: Int) -> URLSessionDownloadTask? {
        lock.lock()
        defer { lock.unlock() }
        return tasksByIdentifier[identifier]
    }

    nonisolated private func removeTask(withIdentifier identifier: Int) {
        lock.lock()
        tasksByIdentifier[identifier] = nil
        lock.unlock()
    }

    nonisolated private func yield(_ event: Event) {
        continuation?.yield(event)
    }
}

extension DownloadSessionClient: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        yield(
            .progress(
                taskIdentifier: downloadTask.taskIdentifier,
                bytesWritten: bytesWritten,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpected: totalBytesExpectedToWrite
            )
        )
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        yield(.finished(taskIdentifier: downloadTask.taskIdentifier, temporaryURL: location))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        defer { removeTask(withIdentifier: task.taskIdentifier) }
        guard let error else { return }

        let nsError = error as NSError
        let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        yield(
            .failed(
                taskIdentifier: task.taskIdentifier,
                errorDomain: nsError.domain,
                errorCode: nsError.code,
                description: nsError.localizedDescription,
                resumeData: resumeData
            )
        )
    }
}
