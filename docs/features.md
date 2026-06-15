# Features

Sommelier is built to be a one-stop-shop for macOS gamers, integrating multiple game sources into a single, beautiful, and native library.

## Unified Game Library

The core feature of Sommelier is its unified game library. Users can manage all their games in one place, regardless of where they were purchased.

### Supported Platforms
Sommelier supports importing and launching games from various platforms:

- **Steam**: Integration with Steam via `steamcmd` or local Steam installations to detect, download, and launch games.
- **Epic Games Store**: Integration via the `legendary` open-source CLI, allowing users to download and launch Epic titles.
- **Amazon Games**: Support via the `nile` CLI tool.
- **macOS Native**: Directly launch macOS applications (`.app`) without any translation layers.
- **Windows Apps**: Manually add and manage standalone `.exe` files and their prefixes.

## Seamless Wine & GPTK Integration

Running Windows games on macOS requires translation layers. Sommelier abstracts this complexity away from the user.

- **Wine Bottles**: Sommelier manages "Bottles" (isolated Wine prefixes) for each game or group of games. Each bottle can have its own configuration, dependencies, and environment variables.
- **Game Porting Toolkit (GPTK)**: Leverages Apple's GPTK to translate DirectX commands to Metal, providing significantly better performance for modern Windows titles on Apple Silicon.
- **Automated Configuration**: When downloading a game from a platform like Epic or Steam, Sommelier automatically sets up the appropriate Wine bottle.

## Tracking & Rich Metadata

Sommelier enriches your library visually and keeps track of your stats.

- **Artwork Retrieval**: Automatically fetches grid covers, hero banners, and icons for games in your library.
- **Play Time Tracking**: Monitors game processes to track and store total play time and last played dates.
- **Status Monitoring**: Shows the real-time status of games (e.g., downloading, installing, updating, running, idle).

## Background Utilities

- **Process Monitoring**: Robustly handles the lifecycle of game processes, ensuring child processes from Wine or CLIs are properly tracked and terminated if needed.
- **Keychain Integration**: Safely stores authentication tokens and credentials for different game stores using the native macOS Keychain.
