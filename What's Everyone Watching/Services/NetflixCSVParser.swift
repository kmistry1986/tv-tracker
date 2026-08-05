import Foundation

class NetflixCSVParser {
    static let shared = NetflixCSVParser()
    
    private init() {}
    
    struct ParsedEntry {
        let title: String
        let date: String
        let showName: String
        let seasonNumber: Int?
        let episodeNumber: Int?
        let isShow: Bool
    }
    
    func parseCSV(content: String) throws -> [ParsedEntry] {
        let lines = content.components(separatedBy: .newlines)
        var entries: [ParsedEntry] = []
        
        for (index, line) in lines.enumerated() {
            if index == 0 { continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            
            let columns = parseCSVLine(line)
            if columns.count >= 2 {
                let title = columns[0].trimmingCharacters(in: .whitespaces)
                let date = columns[1].trimmingCharacters(in: .whitespaces)
                
                let parsed = parseTitle(title, date: date)
                entries.append(parsed)
            }
        }
        
        return entries
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var columns: [String] = []
        var current = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                columns.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        columns.append(current)
        
        return columns
    }
    
    private func parseTitle(_ title: String, date: String) -> ParsedEntry {
        // Try to match season/episode patterns (indicates a TV show)
        let patterns = [
            try! NSRegularExpression(pattern: #"(.+?):\s*Season\s+(\d+):\s*Episode\s+(\d+)"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"(.+?):\s*Season\s+(\d+)"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"(.+?)\s+S(\d+)E(\d+)"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"(.+?)\s+(\d+)x(\d+)"#, options: .caseInsensitive),
            try! NSRegularExpression(pattern: #"(.+?):\s*Part\s+(\d+)"#, options: .caseInsensitive),
        ]

        for pattern in patterns {
            let range = NSRange(title.startIndex..., in: title)
            if let match = pattern.firstMatch(in: title, range: range) {
                if let showRange = Range(match.range(at: 1), in: title) {
                    let showName = String(title[showRange]).trimmingCharacters(in: .whitespaces)
                    var season: Int? = nil
                    var episode: Int? = nil

                    if match.numberOfRanges > 2, let seasonRange = Range(match.range(at: 2), in: title) {
                        season = Int(String(title[seasonRange]))
                    }
                    if match.numberOfRanges > 3, let episodeRange = Range(match.range(at: 3), in: title) {
                        episode = Int(String(title[episodeRange]))
                    }

                    return ParsedEntry(
                        title: title,
                        date: date,
                        showName: showName,
                        seasonNumber: season,
                        episodeNumber: episode,
                        isShow: true
                    )
                }
            }
        }

        // Check if title looks like a TV show based on keywords
        let lowerTitle = title.lowercased()
        let tvKeywords = ["season", "episode", "series", "part", "miniseries", "limited series", "s\\d+e\\d+"]
        let isLikelyShow = tvKeywords.contains { keyword in
            lowerTitle.contains(keyword)
        } || lowerTitle.range(of: #"\bs\d+e\d+"#, options: .regularExpression) != nil

        // Extract just the show name from patterns like "Show: Season X: Episode Y: Episode Title"
        var showName = title
        if let colonIndex = title.firstIndex(of: ":") {
            showName = String(title[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        }

        return ParsedEntry(
            title: title,
            date: date,
            showName: showName,
            seasonNumber: nil,
            episodeNumber: nil,
            isShow: isLikelyShow
        )
    }
}
