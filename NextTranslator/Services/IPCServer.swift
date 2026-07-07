import Darwin
import Foundation

final class IPCServer {
    private let socketPath: String
    private let onText: (String) -> Void
    private let acceptQueue: DispatchQueue
    private let connectionQueue: DispatchQueue
    private let stateLock: NSLock

    private var serverFD: Int32 = -1
    private var running: Bool = false

    init(socketPath: String, onText: @escaping (String) -> Void) {
        self.socketPath = socketPath
        self.onText = onText
        self.acceptQueue = DispatchQueue(label: "com.nexttranslator.ipc.accept")
        self.connectionQueue = DispatchQueue(label: "com.nexttranslator.ipc.connection", attributes: .concurrent)
        self.stateLock = NSLock()
    }

    func start() throws {
        stateLock.lock()
        if running {
            stateLock.unlock()
            return
        }
        stateLock.unlock()

        Darwin.unlink(socketPath)

        let fd: Int32 = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw IPCServerError.socketFailed(Self.errnoMessage("socket"))
        }

        do {
            try bindSocket(fd)
            guard Darwin.listen(fd, SOMAXCONN) == 0 else {
                throw IPCServerError.listenFailed(Self.errnoMessage("listen"))
            }
        } catch {
            Darwin.close(fd)
            Darwin.unlink(socketPath)
            throw error
        }

        stateLock.lock()
        serverFD = fd
        running = true
        stateLock.unlock()

        acceptQueue.async { [weak self] in
            self?.acceptLoop(serverFD: fd)
        }
    }

    func stop() {
        stateLock.lock()
        let fd: Int32 = serverFD
        serverFD = -1
        running = false
        stateLock.unlock()

        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }

        Darwin.unlink(socketPath)
    }
}

private extension IPCServer {
    func bindSocket(_ fd: Int32) throws {
        var address: sockaddr_un = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)

        let maxPathLength: Int = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < maxPathLength else {
            throw IPCServerError.pathTooLong(socketPath)
        }

        socketPath.withCString { pathCString in
            withUnsafeMutablePointer(to: &address.sun_path) { sunPathPointer in
                sunPathPointer.withMemoryRebound(to: CChar.self, capacity: maxPathLength) { sunPath in
                    strncpy(sunPath, pathCString, maxPathLength)
                    sunPath[maxPathLength - 1] = 0
                }
            }
        }

        let bindResult: Int32 = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(fd, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult == 0 else {
            throw IPCServerError.bindFailed(Self.errnoMessage("bind"))
        }
    }

    func acceptLoop(serverFD fd: Int32) {
        while isRunning {
            let clientFD: Int32 = Darwin.accept(fd, nil, nil)

            if clientFD < 0 {
                if isRunning {
                    Self.printError(Self.errnoMessage("accept"))
                    usleep(10_000)
                }
                continue
            }

            connectionQueue.async { [weak self] in
                self?.handleConnection(clientFD)
            }
        }
    }

    func handleConnection(_ clientFD: Int32) {
        defer {
            Darwin.close(clientFD)
        }

        var noSigPipe: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var receiveTimeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(
            clientFD,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        let body: Data
        switch readHTTPBody(from: clientFD) {
        case let .body(data):
            body = data
        case .payloadTooLarge:
            writePayloadTooLargeResponse(to: clientFD)
            return
        }

        writeOKResponse(to: clientFD)

        let text: String = String(data: body, encoding: .utf8) ?? String(decoding: body, as: UTF8.self)
        DispatchQueue.main.async { [onText] in
            onText(text)
        }
    }

    func readHTTPBody(from fd: Int32) -> HTTPBodyReadResult {
        var requestData: Data = Data()
        var headerEndIndex: Data.Index?
        let headerTerminator: Data = Data([13, 10, 13, 10])

        while headerEndIndex == nil {
            let readResult: ReadResult = readChunk(from: fd, into: &requestData)

            switch readResult {
            case .bytes:
                headerEndIndex = requestData.range(of: headerTerminator)?.upperBound
            case .endOfFile:
                return .body(Data())
            case .failure:
                return .body(Data())
            }
        }

        guard let bodyStartIndex: Data.Index = headerEndIndex else {
            return .body(Data())
        }

        let headerData: Data = requestData.subdata(in: 0..<bodyStartIndex)
        let contentLength: Int? = parseContentLength(from: headerData)
        if let contentLength, contentLength > Self.maxContentLength {
            return .payloadTooLarge
        }

        if headerContainsExpectContinue(headerData) {
            writeContinueResponse(to: fd)
        }

        if let contentLength {
            while requestData.count - bodyStartIndex < contentLength {
                let readResult: ReadResult = readChunk(from: fd, into: &requestData)

                switch readResult {
                case .bytes:
                    continue
                case .endOfFile, .failure:
                    let availableLength: Int = max(0, requestData.count - bodyStartIndex)
                    let endIndex: Int = bodyStartIndex + min(availableLength, contentLength)
                    return .body(requestData.subdata(in: bodyStartIndex..<endIndex))
                }
            }

            return .body(requestData.subdata(in: bodyStartIndex..<(bodyStartIndex + contentLength)))
        }

        while true {
            let readResult: ReadResult = readChunk(from: fd, into: &requestData)

            switch readResult {
            case .bytes:
                continue
            case .endOfFile, .failure:
                return .body(requestData.subdata(in: bodyStartIndex..<requestData.count))
            }
        }
    }

    func readChunk(from fd: Int32, into data: inout Data) -> ReadResult {
        var buffer: [UInt8] = Array(repeating: 0, count: 4096)

        while true {
            let bytesRead: Int = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return -1 }
                return Darwin.recv(fd, baseAddress, rawBuffer.count, 0)
            }

            if bytesRead > 0 {
                data.append(contentsOf: buffer.prefix(bytesRead))
                return .bytes(bytesRead)
            }

            if bytesRead == 0 {
                return .endOfFile
            }

            if errno == EINTR {
                continue
            }

            Self.printError(Self.errnoMessage("recv"))
            return .failure
        }
    }

    func parseContentLength(from headerData: Data) -> Int? {
        let headerText: String = String(data: headerData, encoding: .isoLatin1) ?? String(decoding: headerData, as: UTF8.self)
        let lines: [String] = headerText.components(separatedBy: "\r\n")

        for line in lines {
            let parts: [Substring] = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let name: String = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name == "content-length" else { continue }

            let value: String = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if let length = Int(value), length >= 0 {
                return length
            }
        }

        return nil
    }

    func headerContainsExpectContinue(_ headerData: Data) -> Bool {
        let headerText: String = String(data: headerData, encoding: .isoLatin1) ?? String(decoding: headerData, as: UTF8.self)
        let lines: [String] = headerText.components(separatedBy: "\r\n")

        for line in lines {
            let parts: [Substring] = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let name: String = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name == "expect" else { continue }

            let value: String = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if value == "100-continue" {
                return true
            }
        }

        return false
    }

    func writeContinueResponse(to fd: Int32) {
        writeRawResponse(Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), to: fd)
    }

    func writeOKResponse(to fd: Int32) {
        let response: Data = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok".utf8)

        writeRawResponse(response, to: fd)
    }

    func writePayloadTooLargeResponse(to fd: Int32) {
        let body: String = "payload too large"
        let response: Data = Data(
            "HTTP/1.1 413 Payload Too Large\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)".utf8
        )

        writeRawResponse(response, to: fd)
    }

    func writeRawResponse(_ response: Data, to fd: Int32) {
        response.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }

            var bytesWritten: Int = 0

            while bytesWritten < response.count {
                let result: Int = Darwin.send(
                    fd,
                    baseAddress.advanced(by: bytesWritten),
                    response.count - bytesWritten,
                    0
                )

                if result > 0 {
                    bytesWritten += result
                    continue
                }

                if result < 0 && errno == EINTR {
                    continue
                }

                if result < 0 {
                    Self.printError(Self.errnoMessage("send"))
                }
                return
            }
        }
    }

    static let maxContentLength: Int = 1_048_576

    var isRunning: Bool {
        stateLock.lock()
        let currentValue: Bool = running
        stateLock.unlock()
        return currentValue
    }

    static func errnoMessage(_ operation: String) -> String {
        let code: Int32 = errno
        return "IPCServer \(operation) failed: \(String(cString: strerror(code)))"
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    enum ReadResult {
        case bytes(Int)
        case endOfFile
        case failure
    }

    enum HTTPBodyReadResult {
        case body(Data)
        case payloadTooLarge
    }
}

private enum IPCServerError: LocalizedError {
    case socketFailed(String)
    case bindFailed(String)
    case listenFailed(String)
    case pathTooLong(String)

    var errorDescription: String? {
        switch self {
        case let .socketFailed(message),
             let .bindFailed(message),
             let .listenFailed(message):
            return message
        case let .pathTooLong(path):
            return "IPCServer socket path is too long: \(path)"
        }
    }
}
