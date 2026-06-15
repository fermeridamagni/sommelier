# Architecture

Sommelier is primarily a native macOS desktop application built using **SwiftUI**. Its core objective is to wrap around CLI tools and Wine/GPTK to provide a unified GUI for managing game libraries across different platforms.

## Core Technologies

- **UI Framework**: SwiftUI (incorporating Liquid Glass aesthetics for a premium native look).
- **Project Generation**: XcodeGen (via `project.yml`).
- **Data Persistence**: SwiftData (`@Model` macros for storing games, bottles, settings).
- **Concurrency**: Swift Concurrency (`async/await`, `Sendable`).

## Data Models (`Models/`)

The data models represent the fundamental entities in Sommelier. Because they use SwiftData, enum properties (like `Platform` and `GameStatus`) are stored as raw values (strings).

- **`Game`**: The central model representing an application or game. It tracks the game's state (`status`), where it's installed, play time, and links to a specific Wine `Bottle`.
- **`Bottle`**: Represents a Wine prefix/bottle. Contains configuration details like environment variables, the Wine version being used, and its path on disk.
- **`Platform`**: An enum defining the source of a game (Steam, Epic, Amazon, macOS Native, Windows App).
- **`AppSettings`**: Global user preferences and settings for the application.

## Services (`Services/`)

The core business logic is broken down into separate Service/Manager classes. 

- **`LibraryManager`**: Manages scanning, parsing, and storing games from different platforms into SwiftData. It interacts with the CLIs of various platforms to fetch the installed games.
- **`WineManager`**: Handles the creation, configuration, and execution of Wine bottles. It interacts with Apple's Game Porting Toolkit (GPTK) to ensure Windows executables run smoothly on Apple Silicon.
- **`ProcessRunner`**: A utility for executing shell commands and CLI tools asynchronously, capturing standard output and error.
- **`ProcessMonitor`**: Monitors running game processes to track play time and handle crashes or graceful exits.
- **`AuthManager` & `KeychainService`**: Handle user authentication for different store platforms securely using the macOS Keychain.
- **`SystemInfoService`**: Gathers information about the user's macOS system, hardware specs, and available storage.
- **`APIManager`**: Handles external network requests to fetch game metadata, artwork, or interact with web APIs.

## Application State & Paths

The app generates and relies on external tools and user data, which are typically stored in the user's Library directory:
`~/Library/Application Support/Sommelier`

This directory houses the Wine bottles, CLI tools (like `legendary` for Epic or `steamcmd` for Steam), and configuration files.
