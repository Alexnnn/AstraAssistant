//
//  WebSearchService.swift
//  AstraAssistant
//
//  Created by Alex on 10/8/26.
//

import Foundation

struct WebSearchResult: Identifiable, Codable, Hashable {
    let id = UUID()
    let title: String
    let url: String
    let snippet: String
}

final class WebSearchService {
    static let shared = WebSearchService()

    private init() {}

    func search(query: String, limit: Int = 5) async throws -> [WebSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // 1) DDG HTML
        if let htmlResults = try? await searchDuckHTML(query: trimmed, limit: limit),
           !htmlResults.isEmpty {
            return htmlResults
        }

        // 2) DDG Lite
        if let liteResults = try? await searchDuckLite(query: trimmed, limit: limit),
           !liteResults.isEmpty {
            return liteResults
        }

        // 3) Fallback: DuckDuckGo Instant Answer API
        if let instant = try? await searchInstantAnswer(query: trimmed, limit: limit),
           !instant.isEmpty {
            return instant
        }

        return []
    }

    // MARK: - Strategy 1: DDG HTML

    private func searchDuckHTML(query: String, limit: Int) async throws -> [WebSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else { return [] }

        let html = try await fetchHTML(url: url)
        return parseDuckHTML(html, limit: limit)
    }

    private func parseDuckHTML(_ html: String, limit: Int) -> [WebSearchResult] {
        var results: [WebSearchResult] = []

        // Более гибкий паттерн для разных версий вёрстки
        let pattern = #"<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        let matches = regexMatches(pattern: pattern, in: html)

        for match in matches {
            guard results.count < limit else { break }
            guard match.count >= 3 else { continue }

            let rawURL = cleanDuckURL(match[1])
            let title = cleanHTML(match[2])

            if !title.isEmpty, !rawURL.isEmpty {
                results.append(
                    WebSearchResult(
                        title: title,
                        url: rawURL,
                        snippet: ""
                    )
                )
            }
        }

        return deduplicate(results)
    }

    // MARK: - Strategy 2: DDG Lite

    private func searchDuckLite(query: String, limit: Int) async throws -> [WebSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://lite.duckduckgo.com/lite/?q=\(encoded)") else { return [] }

        let html = try await fetchHTML(url: url)
        return parseDuckLite(html, limit: limit)
    }

    private func parseDuckLite(_ html: String, limit: Int) -> [WebSearchResult] {
        var results: [WebSearchResult] = []

        // В lite обычно ссылки выглядят проще
        let pattern = #"<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#
        let matches = regexMatches(pattern: pattern, in: html)

        for match in matches {
            guard results.count < limit else { break }
            guard match.count >= 3 else { continue }

            let rawURL = cleanDuckURL(match[1])
            let title = cleanHTML(match[2])

            guard !rawURL.isEmpty, !title.isEmpty else { continue }
            guard rawURL.hasPrefix("http") else { continue }

            results.append(
                WebSearchResult(
                    title: title,
                    url: rawURL,
                    snippet: ""
                )
            )
        }

        return deduplicate(results)
    }

    // MARK: - Strategy 3: Instant Answer fallback

    private func searchInstantAnswer(query: String, limit: Int) async throws -> [WebSearchResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "https://api.duckduckgo.com/?q=\(encoded)&format=json&no_redirect=1&no_html=1&skip_disambig=0") else {
            return []
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)

        let decoded = try JSONDecoder().decode(DDGInstantResponse.self, from: data)

        var out: [WebSearchResult] = []

        if let abstractText = decoded.AbstractText, !abstractText.isEmpty,
           let abstractURL = decoded.AbstractURL, !abstractURL.isEmpty {
            out.append(
                WebSearchResult(
                    title: decoded.Heading?.isEmpty == false ? decoded.Heading! : "DuckDuckGo Instant Answer",
                    url: abstractURL,
                    snippet: abstractText
                )
            )
        }

        // Related topics
        for item in flattenRelated(decoded.RelatedTopics) {
            guard out.count < limit else { break }
            guard let text = item.Text, !text.isEmpty,
                  let firstURL = item.FirstURL, !firstURL.isEmpty else { continue }

            out.append(
                WebSearchResult(
                    title: text,
                    url: firstURL,
                    snippet: text
                )
            )
        }

        return deduplicate(Array(out.prefix(limit)))
    }

    private func flattenRelated(_ items: [DDGRelatedTopic]?) -> [DDGRelatedTopic] {
        guard let items else { return [] }
        var flat: [DDGRelatedTopic] = []

        for item in items {
            flat.append(item)
            if let nested = item.Topics {
                flat.append(contentsOf: flattenRelated(nested))
            }
        }
        return flat
    }

    // MARK: - Network utils

    private func fetchHTML(url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 (KHTML, like Gecko) Chrome Safari AstraAssistant/1.0",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response: response, data: data)

        return String(data: data, encoding: .utf8) ?? ""
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(
                domain: "WebSearchService",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode): \(body.prefix(200))"]
            )
        }
    }

    // MARK: - Parsing helpers

    private func regexMatches(pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators, .caseInsensitive]) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.map { match in
            (0..<match.numberOfRanges).compactMap { idx in
                guard let r = Range(match.range(at: idx), in: text) else { return nil }
                return String(text[r])
            }
        }
    }

    private func cleanHTML(_ value: String) -> String {
        var result = value
        result = result.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#x27;", with: "'")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanDuckURL(_ value: String) -> String {
        var result = value.replacingOccurrences(of: "&amp;", with: "&")

        // Случай DDG redirect URL с uddg=
        if let components = URLComponents(string: result),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value,
           !uddg.isEmpty {
            return uddg
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deduplicate(_ results: [WebSearchResult]) -> [WebSearchResult] {
        var seen = Set<String>()
        var out: [WebSearchResult] = []

        for item in results {
            guard !seen.contains(item.url) else { continue }
            seen.insert(item.url)
            out.append(item)
        }

        return out
    }
}

// MARK: - DDG Instant Answer models

private struct DDGInstantResponse: Codable {
    let AbstractText: String?
    let AbstractURL: String?
    let Heading: String?
    let RelatedTopics: [DDGRelatedTopic]?
}

private struct DDGRelatedTopic: Codable {
    let Text: String?
    let FirstURL: String?
    let Topics: [DDGRelatedTopic]?
}
