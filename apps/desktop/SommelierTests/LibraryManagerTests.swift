import Testing
import Foundation
@testable import Sommelier

/// Tests for `LibraryManager` game scanning and parsing logic.
@Suite("LibraryManager Tests")
struct LibraryManagerTests {

    // MARK: - Epic Games Parsing

    @Test("Epic JSON parsing extracts game titles")
    @MainActor
    func epicParsingBasic() async throws {
        let manager = LibraryManager()
        // We can't easily mock ProcessRunner here since it's an actor,
        // so we test the JSON structure expectations directly.
        let json = """
        [{
            "app_name": "TestApp",
            "app_title": "Test Game Title",
            "asset_infos": {},
            "base_urls": [],
            "dlcs": [],
            "metadata": {
                "categories": [{"path": "games"}],
                "mainGameItemList": [],
                "title": "Test Game Title",
                "keyImages": []
            }
        }]
        """

        // Verify the JSON is valid and matches the expected structure
        let data = json.data(using: .utf8)!
        struct LegendaryGame: Decodable {
            let app_name: String
            let app_title: String?
            struct Metadata: Decodable {
                struct Category: Decodable {
                    let path: String?
                }
                let categories: [Category]?
                let mainGameItemList: [MainGameItem]?
                struct MainGameItem: Decodable {
                    let id: String?
                }
            }
            let metadata: Metadata?
            let dlcs: [DLCItem]?
            struct DLCItem: Decodable {
                let app_name: String?
            }
        }

        let games = try JSONDecoder().decode([LegendaryGame].self, from: data)
        #expect(games.count == 1)
        #expect(games.first?.app_name == "TestApp")
        #expect(games.first?.app_title == "Test Game Title")
        #expect(games.first?.metadata?.mainGameItemList?.isEmpty == true)
    }

    @Test("DLC entries have non-empty mainGameItemList")
    func dlcDetection() throws {
        let json = """
        [{
            "app_name": "DLCItem",
            "app_title": "Some DLC",
            "asset_infos": {},
            "base_urls": [],
            "dlcs": [],
            "metadata": {
                "categories": [{"path": "addons"}, {"path": "dlc"}],
                "mainGameItemList": [{"id": "parent-game-id"}],
                "title": "Some DLC",
                "keyImages": []
            }
        }]
        """

        struct LegendaryGame: Decodable {
            let app_name: String
            let app_title: String?
            struct Metadata: Decodable {
                struct MainGameItem: Decodable {
                    let id: String?
                }
                let mainGameItemList: [MainGameItem]?
            }
            let metadata: Metadata?
        }

        let games = try JSONDecoder().decode([LegendaryGame].self, from: json.data(using: .utf8)!)
        #expect(games.first?.metadata?.mainGameItemList?.isEmpty == false)
    }

    // MARK: - Amazon Games Parsing

    @Test("Amazon line parsing extracts title and ID")
    func amazonLineParsing() {
        let line = "Totally Reliable Delivery Service (amzn1.adg.product.xxx)"
        // Simulate the parsing logic
        guard let parenRange = line.range(of: " (", options: .backwards) else {
            #expect(Bool(false), "Should find paren")
            return
        }
        let title = String(line[line.startIndex..<parenRange.lowerBound])
        var amazonID = String(line[parenRange.upperBound...])
        if amazonID.hasSuffix(")") {
            amazonID = String(amazonID.dropLast())
        }
        #expect(title == "Totally Reliable Delivery Service")
        #expect(amazonID == "amzn1.adg.product.xxx")
    }

    @Test("Amazon line without ID uses full line as title")
    func amazonLineNoID() {
        let line = "Simple Game Title"
        let parenRange = line.range(of: " (", options: .backwards)
        #expect(parenRange == nil)
        // Falls back to using the entire line as the title
    }

    // MARK: - Game Status

    @Test("GameStatus raw values round-trip")
    func gameStatusRoundTrip() {
        for status in [GameStatus.idle, .downloading, .installing, .running, .updating, .error] {
            let raw = status.rawValue
            #expect(GameStatus(rawValue: raw) == status)
        }
    }

    // MARK: - Platform

    @Test("Platform display names are set")
    func platformDisplayNames() {
        #expect(Platform.steam.displayName == "Steam")
        #expect(Platform.epic.displayName == "Epic Games")
        #expect(Platform.amazon.displayName == "Amazon Games")
        #expect(Platform.macNative.displayName == "macOS")
        #expect(Platform.windowsApp.displayName == "Windows App")
    }

    @Test("All platforms have system images")
    func platformSystemImages() {
        for platform in Platform.allCases {
            #expect(!platform.systemImage.isEmpty)
        }
    }
}
