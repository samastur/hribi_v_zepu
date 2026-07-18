import Foundation

public enum HikeURL {
    /// Validates a hribi.net hike URL. Returns a normalized https URL without fragment, or nil.
    public static func validate(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let host = components.host?.lowercased(),
              host == "hribi.net" || host.hasSuffix(".hribi.net")
        else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "izlet" else { return nil }
        components.scheme = "https"
        components.fragment = nil
        return components.url
    }

    /// Extracts the hike slug (the path segment after "izlet").
    public static func slug(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "izlet" else { return nil }
        return parts[1]
    }
}
