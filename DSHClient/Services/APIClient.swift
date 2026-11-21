import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case unauthorized
    case server(String)
    case transport(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "服务器地址格式不正确"
        case .unauthorized:
            return "配对码不正确或已失效"
        case .server(let message):
            return message
        case .transport(let message):
            return "网络连接失败：\(message)"
        case .decoding(let message):
            return "返回数据无法解析：\(message)"
        }
    }
}

final class APIClient {
    let baseURL: URL
    let token: String
    private let session: URLSession

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["Accept": "application/json"]
        self.session = URLSession(configuration: configuration)
    }

    func get<T: Decodable>(_ path: String, completion: @escaping (Result<T, APIError>) -> Void) {
        perform(method: "GET", path: path, body: nil, completion: completion)
    }

    func post<T: Decodable>(_ path: String, body: [String: Any]? = nil, completion: @escaping (Result<T, APIError>) -> Void) {
        perform(method: "POST", path: path, body: body, completion: completion)
    }

    private func perform<T: Decodable>(method: String, path: String, body: [String: Any]?,
                                       completion: @escaping (Result<T, APIError>) -> Void) {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            completion(.failure(.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
        } else if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }

        session.dataTask(with: request) { data, response, error in
            func finish(_ value: Result<T, APIError>) {
                DispatchQueue.main.async { completion(value) }
            }

            if let error = error {
                return finish(.failure(.transport(error.localizedDescription)))
            }
            guard let http = response as? HTTPURLResponse else {
                return finish(.failure(.transport("没有收到服务器响应")))
            }

            let body = data ?? Data()

            if http.statusCode == 401 {
                return finish(.failure(.unauthorized))
            }
            guard (200...299).contains(http.statusCode) else {
                let message = (try? JSONDecoder().decode(ErrorEnvelope.self, from: body))?.error?.message
                return finish(.failure(.server(message ?? "服务器返回 HTTP \(http.statusCode)")))
            }

            do {
                finish(.success(try JSONDecoder().decode(T.self, from: body)))
            } catch {
                finish(.failure(.decoding(error.localizedDescription)))
            }
        }.resume()
    }
}

enum ServerAddress {
    /// 接受 "192.168.1.5"、"192.168.1.5:8787"、"http://host:8787/" 等写法。
    static func normalize(_ input: String) -> URL? {
        var text = input.trimmed
        guard !text.isEmpty else { return nil }
        if !text.contains("://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text) else { return nil }
        guard let host = components.host, !host.isEmpty else { return nil }
        if components.scheme != "http" && components.scheme != "https" {
            components.scheme = "http"
        }
        if components.port == nil {
            components.port = 8787
        }
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    /// 允许用户省略中间横线。
    static func normalizeCode(_ input: String) -> String {
        let cleaned = input.uppercased().replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "－", with: "-")
        if cleaned.count == 8 && !cleaned.contains("-") {
            let index = cleaned.index(cleaned.startIndex, offsetBy: 4)
            return String(cleaned[..<index]) + "-" + String(cleaned[index...])
        }
        return cleaned
    }
}
