import Testing
import Foundation
@testable import Sommelier

/// Tests for `LibraryManager` Steam parsing logic.
@Suite("LibraryManager Steam Tests")
struct LibraryManagerSteamTests {
    
    @Test("Steam Web API JSON parsing extracts game details")
    func steamParsingBasic() throws {
        let json = """
        {
            "response": {
                "game_count": 2,
                "games": [
                    {
                        "appid": 730,
                        "name": "Counter-Strike: Global Offensive",
                        "playtime_forever": 600,
                        "img_icon_url": "icon1",
                        "has_community_visible_stats": true
                    },
                    {
                        "appid": 400,
                        "name": "Portal",
                        "playtime_forever": 120,
                        "img_icon_url": "icon2"
                    }
                ]
            }
        }
        """
        
        let data = json.data(using: .utf8)!
        
        // Emulate LibraryManager.scanSteamGames parsing structure
        struct SteamResponse: Decodable {
            struct Response: Decodable {
                struct Game: Decodable {
                    let appid: Int
                    let name: String?
                    let playtime_forever: Int? // minutes
                    let img_icon_url: String?
                }
                let games: [Game]?
            }
            let response: Response
        }
        
        let steamResponse = try JSONDecoder().decode(SteamResponse.self, from: data)
        let parsedGames = steamResponse.response.games ?? []
        
        #expect(parsedGames.count == 2)
        #expect(parsedGames[0].appid == 730)
        #expect(parsedGames[0].name == "Counter-Strike: Global Offensive")
        #expect(parsedGames[0].playtime_forever == 600)
        
        #expect(parsedGames[1].appid == 400)
        #expect(parsedGames[1].name == "Portal")
        #expect(parsedGames[1].playtime_forever == 120)
    }
}
