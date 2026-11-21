import Foundation

/// 读取桥接服务的 Server-Sent-Events 流，断线后自动重连（带退避）。
final class SSEClient: NSObject {
    private let url: URL
    private let token: String

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var stopped = true
    private var retryCount = 0
    private var lastEventId = ""
    private var lastActivity = Date()
    private var watchdog: Timer?
    private var reconnectWork: DispatchWorkItem?

    /// 收到一条事件（主线程回调）。
    var onEvent: (([String: Any]) -> Void)?
    /// 连接状态变化（主线程回调）。
    var onConnectionChange: ((Bool) -> Void)?
    /// 配对码失效（HTTP 401），此时不再重试。
    var onAuthFailure: (() -> Void)?

    init(url: URL, token: String) {
        self.url = url
        self.token = token
        super.init()
    }

    deinit {
        stopped = true
        reconnectWork?.cancel()
        watchdog?.invalidate()
        session?.invalidateAndCancel()
    }

    func connect() {
        guard stopped else { return }
        stopped = false
        retryCount = 0
        open()
    }

    func disconnect() {
        stopped = true
        reconnectWork?.cancel()
        reconnectWork = nil
        closeSession()
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChange?(false)
        }
    }

    // MARK: - 连接

    private func open() {
        guard !stopped, session == nil else { return }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 0
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility

        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if !lastEventId.isEmpty {
            request.setValue(lastEventId, forHTTPHeaderField: "Last-Event-ID")
        }

        lastActivity = Date()
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
        startWatchdog()
    }

    private func closeSession() {
        let current = session
        session = nil
        task = nil
        buffer.removeAll()
        let timer = watchdog
        watchdog = nil
        DispatchQueue.main.async {
            timer?.invalidate()
        }
        current?.invalidateAndCancel()
    }

    private func scheduleReconnect() {
        guard !stopped, reconnectWork == nil else { return }
        retryCount += 1
        let delay = min(pow(2.0, Double(retryCount)), 15.0)
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.reconnectWork = nil
            self.open()
        }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startWatchdog() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.watchdog?.invalidate()
            self.watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if Date().timeIntervalSince(self.lastActivity) > 45 {
                    self.task?.cancel()
                }
            }
        }
    }

    // MARK: - 解析

    private func consume(_ data: Data) {
        buffer.append(data)

        let separator = Data([10, 10]) // "\n\n"
        while let range = buffer.range(of: separator) {
            let frameData = buffer.subdata(in: 0..<range.lowerBound)
            buffer.removeSubrange(0..<range.upperBound)
            guard !frameData.isEmpty,
                  let text = String(data: frameData, encoding: .utf8) else { continue }
            handleFrame(text)
        }

        if buffer.count > 1_000_000 {
            buffer.removeAll()
        }
    }

    private func handleFrame(_ frame: String) {
        var dataLines: [String] = []

        for rawLine in frame.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(rawLine)
            if line.hasSuffix("\r") {
                line = String(line.dropLast())
            }
            if line.isEmpty || line.hasPrefix(":") { continue }

            if line.hasPrefix("data:") {
                var value = String(line.dropFirst(5))
                if value.hasPrefix(" ") { value = String(value.dropFirst()) }
                dataLines.append(value)
            } else if line.hasPrefix("id:") {
                lastEventId = String(line.dropFirst(3)).trimmed
            }
        }

        guard !dataLines.isEmpty,
              let data = dataLines.joined(separator: "\n").data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else { return }

        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(json)
        }
    }
}

// MARK: - URLSessionDataDelegate

extension SSEClient: URLSessionDataDelegate {
    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard session === self.session else {
            completionHandler(.cancel)
            return
        }

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            completionHandler(.cancel)
            if http.statusCode == 401 {
                stopped = true
                closeSession()
                DispatchQueue.main.async { [weak self] in
                    self?.onConnectionChange?(false)
                    self?.onAuthFailure?()
                }
            }
            return
        }

        completionHandler(.allow)

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.retryCount = 0
            self.onConnectionChange?(true)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard session === self.session else { return }
        lastActivity = Date()
        consume(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let isCurrent = (session === self.session)
        guard isCurrent else { return }

        closeSession()
        DispatchQueue.main.async { [weak self] in
            self?.onConnectionChange?(false)
        }
        scheduleReconnect()
    }
}
