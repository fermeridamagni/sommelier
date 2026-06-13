import Foundation

// MARK: - API Error Types

/// Errors that can occur during external API calls.
enum APIError: Error, LocalizedError, Sendable {
    /// The URL could not be constructed from the given components.
    case invalidURL

    /// A network-level error occurred (no connectivity, DNS failure, timeout).
    case networkError(String)

    /// The API response could not be decoded into the expected model.
    case decodingError(String)

    /// The API key is missing or the server returned 401/403.
    case unauthorized

    /// The API rate limit has been exceeded (HTTP 429).
    case rateLimited

    /// The server returned an unexpected HTTP status code.
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid URL. Please check the request parameters."
        case .networkError(let message):
            "Network error: \(message)"
        case .decodingError(let message):
            "Failed to decode API response: \(message)"
        case .unauthorized:
            "Unauthorized. Please check your API key."
        case .rateLimited:
            "API rate limit exceeded. Please wait and try again."
        case .httpError(let code):
            "HTTP error \(code)"
        }
    }
}

// MARK: - Response Models

/// A generic wrapper for SteamGridDB API responses.
///
/// The SteamGridDB API always wraps results in `{ "success": bool, "data": [...] }`.
struct SteamGridDBResponse<T: Decodable>: Decodable {
    /// Whether the API call was successful.
    let success: Bool

    /// The response payload, present when `success` is `true`.
    let data: T?
}

/// A game entry returned by SteamGridDB's search endpoint.
struct SteamGridDBGame: Decodable, Sendable, Identifiable {
    /// SteamGridDB's internal game ID.
    let id: Int

    /// The game's display name.
    let name: String

    /// Release date as a Unix timestamp, if available.
    let release_date: Int?

    /// Whether this game has been verified by SteamGridDB moderators.
    let verified: Bool?

    /// Types of artwork available for this game.
    let types: [String]?
}

/// An artwork image result from SteamGridDB (covers, heroes, icons).
struct ArtworkResult: Decodable, Sendable, Identifiable {
    /// Unique artwork ID.
    let id: Int

    /// The upvote score for this artwork.
    let score: Int?

    /// Style category (e.g. "alternate", "blurred", "material").
    let style: String?

    /// Width in pixels.
    let width: Int?

    /// Height in pixels.
    let height: Int?

    /// Whether the image is animated (GIF/WEBM).
    let nsfw: Bool?

    /// Whether the image contains humor.
    let humor: Bool?

    /// Direct URL to the image file.
    let url: String

    /// URL to a thumbnail version.
    let thumb: String?

    /// Tags applied to this artwork.
    let tags: [String]?

    /// The uploader's SteamGridDB author info.
    let author: Author?

    /// Represents an artwork uploader.
    struct Author: Decodable, Sendable {
        let name: String?
        let steam64: String?
        let avatar: String?
    }
}

/// Basic game info from the Steam Web API's owned games endpoint.
struct SteamGameInfo: Decodable, Sendable {
    /// The Steam Application ID.
    let appid: Int

    /// The game's display name.
    let name: String?

    /// Total playtime in minutes.
    let playtime_forever: Int?

    /// URL fragment for the game's icon on Steam CDN.
    let img_icon_url: String?

    /// Whether the game supports macOS.
    let has_mac_support: Bool?

    /// Whether the game supports Linux.
    let has_linux_support: Bool?
}

// MARK: - API Manager

/// An actor for making authenticated requests to external APIs.
///
/// Currently supports:
/// - **SteamGridDB** — Game artwork (covers, heroes, icons) for the library UI
/// - **Steam Web API** — Fetching owned games for a Steam user
///
/// API keys are loaded from the Keychain on each request so they're always
/// up-to-date if the user changes them in Settings.
actor APIManager {
    /// SteamGridDB API base URL.
    private let steamGridDBBaseURL = "https://www.steamgriddb.com/api/v2"

    /// Shared `URLSession` for all network requests.
    private let session: URLSession

    /// Creates a new `APIManager` with the given URL session.
    ///
    /// - Parameter session: The URL session for network calls.
    ///   Defaults to `.shared`.
    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - SteamGridDB: Search

    /// Searches SteamGridDB for games matching the given query.
    ///
    /// Uses the `/search/autocomplete/{term}` endpoint which returns
    /// partial matches suitable for search-as-you-type UIs.
    ///
    /// - Parameter query: The search term (e.g. "cyberpunk").
    /// - Returns: An array of matching `SteamGridDBGame` entries.
    /// - Throws: `APIError` on network, auth, or decoding failures.
    func searchGame(query: String) async throws -> [SteamGridDBGame] {
        guard let encodedQuery = query.addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed
        ) else {
            throw APIError.invalidURL
        }

        let urlString = "\(steamGridDBBaseURL)/search/autocomplete/\(encodedQuery)"
        let response: SteamGridDBResponse<[SteamGridDBGame]> = try await steamGridDBRequest(
            urlString: urlString
        )
        return response.data ?? []
    }

    // MARK: - SteamGridDB: Artwork

    /// Fetches cover/grid artwork for a game from SteamGridDB.
    ///
    /// - Parameter gameID: The SteamGridDB game ID.
    /// - Returns: Available cover artwork sorted by score.
    /// - Throws: `APIError` on network, auth, or decoding failures.
    func fetchCovers(gameID: Int) async throws -> [ArtworkResult] {
        let urlString = "\(steamGridDBBaseURL)/grids/game/\(gameID)"
        let response: SteamGridDBResponse<[ArtworkResult]> = try await steamGridDBRequest(
            urlString: urlString
        )
        return response.data ?? []
    }

    /// Fetches hero/banner artwork for a game from SteamGridDB.
    ///
    /// - Parameter gameID: The SteamGridDB game ID.
    /// - Returns: Available hero artwork sorted by score.
    /// - Throws: `APIError` on network, auth, or decoding failures.
    func fetchHeroes(gameID: Int) async throws -> [ArtworkResult] {
        let urlString = "\(steamGridDBBaseURL)/heroes/game/\(gameID)"
        let response: SteamGridDBResponse<[ArtworkResult]> = try await steamGridDBRequest(
            urlString: urlString
        )
        return response.data ?? []
    }

    /// Fetches icon artwork for a game from SteamGridDB.
    ///
    /// - Parameter gameID: The SteamGridDB game ID.
    /// - Returns: Available icon artwork sorted by score.
    /// - Throws: `APIError` on network, auth, or decoding failures.
    func fetchIcons(gameID: Int) async throws -> [ArtworkResult] {
        let urlString = "\(steamGridDBBaseURL)/icons/game/\(gameID)"
        let response: SteamGridDBResponse<[ArtworkResult]> = try await steamGridDBRequest(
            urlString: urlString
        )
        return response.data ?? []
    }

    // MARK: - Image Downloading

    /// Downloads an image from a URL and saves it to a local file path.
    ///
    /// Used to cache game artwork (covers, heroes, icons) locally so the
    /// app doesn't re-download images on every launch.
    ///
    /// - Parameters:
    ///   - urlString: The remote URL of the image.
    ///   - destinationPath: The local file path to save the image to.
    /// - Throws: `APIError` on network failure, or file system errors.
    func downloadImage(from urlString: String, to destinationPath: String) async throws {
        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Ensure the parent directory exists.
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let parentDir = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parentDir,
            withIntermediateDirectories: true
        )

        try data.write(to: destinationURL, options: .atomic)
    }

    // MARK: - Steam Web API

    /// Fetches a user's owned Steam games via the Steam Web API.
    ///
    /// Calls `IPlayerService/GetOwnedGames/v1` with `include_appinfo=true`
    /// to get game names and metadata.
    ///
    /// - Parameters:
    ///   - apiKey: A valid Steam Web API key.
    ///   - steamID: The user's 64-bit Steam ID.
    /// - Returns: An array of `SteamGameInfo` for all owned games.
    /// - Throws: `APIError` on network, auth, or decoding failures.
    func fetchOwnedSteamGames(
        apiKey: String,
        steamID: String
    ) async throws -> [SteamGameInfo] {
        let urlString = "https://api.steampowered.com/IPlayerService/GetOwnedGames/v1/"
            + "?key=\(apiKey)"
            + "&steamid=\(steamID)"
            + "&include_appinfo=true"
            + "&include_played_free_games=true"
            + "&format=json"

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response)

        struct OwnedGamesResponse: Decodable {
            struct Response: Decodable {
                let games: [SteamGameInfo]?
            }
            let response: Response
        }

        do {
            let decoded = try JSONDecoder().decode(OwnedGamesResponse.self, from: data)
            return decoded.response.games ?? []
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers

    /// Makes an authenticated GET request to the SteamGridDB API.
    ///
    /// Loads the API key from Keychain on every call so it's always current.
    /// The key is sent in the `Authorization: Bearer <key>` header.
    ///
    /// - Parameter urlString: The full URL string to request.
    /// - Returns: The decoded `SteamGridDBResponse` wrapper.
    /// - Throws: `APIError` on any failure.
    private func steamGridDBRequest<T: Decodable>(
        urlString: String
    ) async throws -> SteamGridDBResponse<T> {
        guard let apiKey = KeychainService.read(key: KeychainService.Keys.steamGridDBAPIKey) else {
            throw APIError.unauthorized
        }

        guard let url = URL(string: urlString) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error.localizedDescription)
        }

        try validateHTTPResponse(response)

        do {
            return try JSONDecoder().decode(SteamGridDBResponse<T>.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }

    /// Validates an HTTP response, throwing appropriate `APIError`s for
    /// non-success status codes.
    ///
    /// - Parameter response: The `URLResponse` to validate.
    /// - Throws: `APIError.unauthorized` for 401/403,
    ///   `APIError.rateLimited` for 429, `APIError.httpError` for other failures.
    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }

        switch httpResponse.statusCode {
        case 200...299:
            return // Success range — no error.
        case 401, 403:
            throw APIError.unauthorized
        case 429:
            throw APIError.rateLimited
        default:
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}
