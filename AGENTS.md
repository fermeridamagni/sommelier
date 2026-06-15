# Project Instructions

For a complete summary of the app state, architecture, and features, please read the documentation in the [`/docs`](./docs/index.md) directory.

## Rules

- **Document and explain**: Always explain what the code is for and document significant changes.
- **Build and test**: Ensure that every feature or fix is built and tested before completing a task.
- **Context7 MCP**: Use the Context7 MCP to get up-to-date info.
- **Codegraph MCP**: Get pre-indexed repository knowledge about the project using the Codegraph MCP.
- **Bun**: Always use Bun as the package manager and runtime environment instead of npm or Node.js.
- **TypeScript**: Always use TypeScript instead of Javascript.
- **Formatting & Linting**: Use Ultracite (Biome's zero-config preset) for code formatting and linting.

## Project Structure

The project is structured as a monorepo containing multiple apps and packages.

- `apps/desktop` - A native desktop app for macOS built with SwiftUI and Liquid Glass.
- `apps/web` - Marketing website built with Astro, Bun, TypeScript, and Tailwind CSS.

See [`/docs/project-structure.md`](./docs/project-structure.md) for more detailed information.

## Architecture & Features

Sommelier is a macOS application designed to run Windows games seamlessly using Wine and Apple's Game Porting Toolkit (GPTK). It supports integrating with platforms like Steam, Epic Games, and Amazon Games.

- Read more about the **Architecture** in [`/docs/architecture.md`](./docs/architecture.md)
- Read more about the **Features** in [`/docs/features.md`](./docs/features.md)

## References

- [Ultracite Code Standards](ULTRACITE.md)
