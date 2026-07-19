import Foundation

public enum HikeURL {
    /// Slugs become on-disk folder names — restrict to a safe charset (also blocks "." / "..").
    private static func isValidSlug(_ slug: String) -> Bool {
        !slug.isEmpty && slug.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
    }

    /// Validates a hribi.net hike URL. Returns a normalized https URL without fragment, or nil.
    public static func validate(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)(\'\"")

        // Try the string as-is
        var toValidate = trimmed
        if let url = validateString(toValidate) {
            return url
        }

        // Try with trailing punctuation stripped
        toValidate = trimmed.trimmingCharacters(in: trailingPunctuation)
        if toValidate != trimmed {
            return validateString(toValidate)
        }

        return nil
    }

    private static func validateString(_ string: String) -> URL? {
        guard var components = URLComponents(string: string),
              let host = components.host?.lowercased(),
              host == "hribi.net" || host.hasSuffix(".hribi.net")
        else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "izlet", isValidSlug(parts[1]) else { return nil }

        // Reject URLs with trailing punctuation in the path
        let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?)(\'\"")
        if let lastPart = parts.last, lastPart.rangeOfCharacter(from: trailingPunctuation) != nil {
            return nil
        }

        components.scheme = "https"
        components.fragment = nil
        return components.url
    }

    /// Scans free text for the first token that is a valid hribi.net hike URL and returns it normalized.
    public static func extractHikeURL(fromText text: String) -> URL? {
        let tokens = text.components(separatedBy: .whitespacesAndNewlines)
        return tokens.lazy.compactMap { validate($0) }.first
    }

    /// Extracts the hike slug (the path segment after "izlet").
    public static func slug(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, parts[0] == "izlet", isValidSlug(parts[1]) else { return nil }
        return parts[1]
    }
}
