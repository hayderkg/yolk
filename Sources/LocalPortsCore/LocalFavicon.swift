import Foundation

public enum FaviconPolicy {
    public static func isLocal(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        if ["localhost", "::1", "[::1]"].contains(host) { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.first == "127" && parts.allSatisfy {
            !$0.isEmpty && $0.allSatisfy(\.isNumber) && UInt8($0) != nil
        }
    }

    public static func sameOrigin(_ candidate: URL, _ origin: URL) -> Bool {
        func port(_ url: URL) -> Int { url.port ?? (url.scheme == "https" ? 443 : 80) }
        return isLocal(candidate) && isLocal(origin) && candidate.scheme == origin.scheme &&
            candidate.host?.lowercased() == origin.host?.lowercased() && port(candidate) == port(origin)
    }

    public static func iconURLs(in html: String, origin: URL) -> [URL] {
        guard let links = try? NSRegularExpression(pattern: #"<link\b[^>]*>"#, options: .caseInsensitive),
              let attributes = try? NSRegularExpression(pattern: #"([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return [] }
        let source = html as NSString
        var result: [URL] = []
        for match in links.matches(in: html, range: NSRange(location: 0, length: source.length)) {
            let tag = source.substring(with: match.range) as NSString
            var values: [String: String] = [:]
            for attribute in attributes.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)) {
                let key = tag.substring(with: attribute.range(at: 1)).lowercased()
                if let group = (2...4).first(where: { attribute.range(at: $0).location != NSNotFound }) {
                    values[key] = tag.substring(with: attribute.range(at: group))
                }
            }
            let relations = (values["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            guard relations.contains("icon") || relations.contains("apple-touch-icon"),
                  let href = values["href"],
                  let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: origin)?.absoluteURL,
                  sameOrigin(url, origin), !result.contains(url) else { continue }
            result.append(url)
            if result.count == 3 { break }
        }
        return result
    }

    /// SVGs are decoded as images only, with embedded/local-fragment resources.
    public static func isSelfContainedSVG(_ data: Data) -> Bool {
        guard let source = String(data: data, encoding: .utf8),
              !source.lowercased().contains("<!doctype"), !source.lowercased().contains("<!entity"),
              !source.lowercased().contains("@import") else { return false }
        let delegate = SVGValidator()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        return parser.parse() && delegate.valid && delegate.sawSVG
    }
}

private final class SVGValidator: NSObject, XMLParserDelegate {
    var valid = true
    var sawSVG = false
    private var styleText: String?
    private func checkReferences(_ string: String) {
        guard let expression = try? NSRegularExpression(pattern: #"url\s*\(\s*['"]?([^)'"\s]+)"#, options: .caseInsensitive) else { return }
        let value = string as NSString
        for match in expression.matches(in: string, range: NSRange(location: 0, length: value.length)) {
            if !value.substring(with: match.range(at: 1)).hasPrefix("#") { valid = false }
        }
        // CSS escapes can disguise resource URLs; ordinary favicon paths do not need them.
        if string.contains("\\") { valid = false }
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        let name = elementName.lowercased()
        if name == "svg" { sawSVG = true }
        if ["script", "foreignobject", "image"].contains(name) { valid = false }
        if name == "style" { styleText = "" }
        for (key, value) in attributes {
            if key.lowercased().hasSuffix("href"), !value.hasPrefix("#") { valid = false }
            checkReferences(value)
        }
        if !valid { parser.abortParsing() }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if styleText != nil { styleText! += string }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if styleText != nil { styleText! += String(decoding: CDATABlock, as: UTF8.self) }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName.lowercased() == "style", let style = styleText {
            checkReferences(style)
            styleText = nil
            if !valid { parser.abortParsing() }
        }
    }
}

public enum LocalFavicon {
    public static func load(from origin: URL) async -> Data? {
        guard FaviconPolicy.isLocal(origin) else { return nil }
        let conventional = origin.appendingPathComponent("favicon.ico")
        if let response = await LimitedLocalRequest.fetch(conventional, origin: origin), response.isImage { return response.data }
        guard !Task.isCancelled else { return nil }
        var candidates: [URL] = []
        if let page = await LimitedLocalRequest.fetch(origin, origin: origin, limit: 65_536),
           page.mimeType.contains("html") {
            candidates = FaviconPolicy.iconURLs(in: String(decoding: page.data, as: UTF8.self), origin: origin)
        }
        candidates += [origin.appendingPathComponent("favicon.png"), origin.appendingPathComponent("favicon.svg")]
        for url in candidates where url != conventional {
            if Task.isCancelled { return nil }
            if let response = await LimitedLocalRequest.fetch(url, origin: origin), response.isImage { return response.data }
        }
        return nil
    }
}

private struct LocalResponse {
    let data: Data
    let mimeType: String
    var isImage: Bool {
        if mimeType.contains("svg") { return FaviconPolicy.isSelfContainedSVG(data) }
        let prefix = Array(data.prefix(8))
        // Recognize binary favicon/image formats even when the server uses application/octet-stream.
        return prefix.starts(with: [0, 0, 1, 0]) || prefix.starts(with: [137, 80, 78, 71]) ||
            prefix.starts(with: [255, 216, 255]) || prefix.starts(with: [71, 73, 70, 56]) ||
            (mimeType.hasPrefix("image/") && !mimeType.contains("svg"))
    }
}

/// A short-lived, bounded, credential-free request. The delegate queue serializes all mutable state.
private final class LimitedLocalRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let origin: URL
    private let limit: Int
    private var data = Data()
    private var mimeType = ""
    private var redirects = 0
    private var continuation: CheckedContinuation<LocalResponse?, Never>?
    private var session: URLSession?

    private init(origin: URL, limit: Int) { self.origin = origin; self.limit = limit }

    static func fetch(_ url: URL, origin: URL, limit: Int = 524_288) async -> LocalResponse? {
        guard FaviconPolicy.sameOrigin(url, origin) else { return nil }
        let loader = LimitedLocalRequest(origin: origin, limit: limit)
        return await withCheckedContinuation { continuation in
            loader.continuation = continuation
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 1.5
            configuration.timeoutIntervalForResource = 2.5
            configuration.urlCache = nil
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.connectionProxyDictionary = [:]
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .utility
            let session = URLSession(configuration: configuration, delegate: loader, delegateQueue: queue)
            loader.session = session
            var request = URLRequest(url: url)
            request.setValue("image/*,text/html;q=0.5", forHTTPHeaderField: "Accept")
            request.setValue("LocalPorts/1.1", forHTTPHeaderField: "User-Agent")
            session.dataTask(with: request).resume()
        }
    }

    private func finish(_ result: LocalResponse?) {
        continuation?.resume(returning: result)
        continuation = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= Int64(limit) else {
            completionHandler(.cancel); finish(nil); return
        }
        mimeType = response.mimeType?.lowercased() ?? ""
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        guard data.count + chunk.count <= limit else { finish(nil); return }
        data.append(chunk)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        finish(error == nil && !data.isEmpty ? LocalResponse(data: data, mimeType: mimeType) : nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard redirects < 2, let url = request.url, FaviconPolicy.sameOrigin(url, origin) else {
            completionHandler(nil); finish(nil); return
        }
        redirects += 1
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}
