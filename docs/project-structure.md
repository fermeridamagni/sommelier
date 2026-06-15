# Project Structure

Sommelier uses a monorepo setup powered by **Bun** and **TurboRepo** to manage its different applications and shared packages. 

## Root Directory

- `bun.lock`, `package.json`: Dependency management and scripts managed via Bun.
- `turbo.json`: TurboRepo configuration for caching and task running.
- `biome.jsonc`: Linting and formatting rules via Biome (Ultracite preset).
- `AGENTS.md`: Instruction set and rules for AI agents and contributors working on the project.
- `docs/`: Extensive project documentation.

## Applications (`apps/`)

### `apps/desktop` - Sommelier macOS App
The primary application source code.
- **Language**: Swift
- **Framework**: SwiftUI
- **Project Structure**: Uses XcodeGen (`project.yml`) instead of committing `.xcodeproj` directly. 
- **Subdirectories**: Contains the standard iOS/macOS MVVM structure (`Models`, `Views`, `ViewModels`, `Services`).

### `apps/web` - Marketing Website
A web frontend meant for marketing and distribution of the Sommelier app.
- **Tech Stack**: Astro, Bun, TypeScript, Tailwind CSS.

## Packages (`packages/`)

*(If applicable, this directory contains shared code used across multiple applications. For example, shared TypeScript definitions or ESLint/Biome configurations).*

## Tooling and Environment

- **Bun**: Used across the monorepo as the package manager and runner.
- **Ultracite**: A zero-config preset for Biome ensuring consistent code style across all web and config files.
- **Context7 / Codegraph**: Used by LLM tools to parse and query the repository efficiently.
