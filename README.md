# 2DO board

In-world teleporter board for 2DO events server.

- Get the latest version in-world at Speculoos Lab: [speculoos.world:8002/Lab](hop://speculoos.world:8002/Lab/)
- or from [Kitely Market](https://www.kitely.com/market/product/50129545)

## Features

- Fetches upcoming events from [2do.directory](https://2do.directory) (or a self-hosted aggregator)
- Touch-to-teleport: touching an event row teleports you to the event location
- Two rendering modes:
  - **Server renderer** (default): server-side PNG image applied via `osSetDynamicTextureURLBlendFace`
  - **OSdraw renderer** (`renderer=osdraw`): client-side text rendering via `osDrawText` / `osDynamicTextureDataBlendFace`
- Auto-refreshes at a configurable interval
- Applies texture to specific prim faces, with automatic ratio detection for non-square faces

## Installation from sources

- Put the content of `2DO board.lsl` in a script named "2DO board"
- Put the content of `2DO Read me` in a notecard named "2DO Read me"
- Let the magic happen

## Configuration

Settings are read from the "Configuration" notecard inside the prim. Keys are case-insensitive and accept both `camelCase` and `ALL_CAPS_UNDERSCORE` forms.

### Source and rendering

| Key | Default | Description |
|-----|---------|-------------|
| `eventsURL` | `https://2do.directory/api/v3/events/lsl` | Custom events source URL. Leave empty to use the official API. Required for osdraw renderer with a custom source. |
| `renderer` | `server` | `server` = server-side PNG (API v3); `osdraw` = client-side LSL text renderer |
| `ratio` | `0` | Face aspect ratio (width/height); `0` = auto-detect from prim scale |
| `ratioCap` | `0.25` | Skip faces whose ratio is outside `[ratioCap, 1/ratioCap]` (e.g. extreme side faces) |
| `activeSides` | `2,4` | Comma-separated list of prim faces to apply the texture to |
| `textureWidth` | `512` | Texture resolution (width in pixels) |
| `textureHeight` | `512` | Texture resolution (height in pixels) |
| `refreshTime` | `1800` | Refresh interval in seconds |
| `showPastEvents` | `FALSE` | Include events that have already ended |

### Banner

| Key | Default | Description |
|-----|---------|-------------|
| `bannerImageURL` | `https://2do.directory/2do-logo.png` | URL of the banner/logo image |
| `bannerHeight` | `90` | Banner area height in pixels |

### Colors (LSL renderer)

| Key | Default | Description |
|-----|---------|-------------|
| `backgroundColor` | `white` | Background color |
| `fontColor` | `black` | Default text color |
| `colorPast` | `lightGray` | Color for past events |
| `colorStarted` | `darkGreen` | Color for ongoing events |
| `colorSoon` | `darkBlue` | Color for events starting soon |
| `colorToday` | `gray` | Color for today's events |
| `colorLater` | `lightGray` | Color for later events |
| `colorHour` | `darkMagenta` | Color for hour markers |

### Fonts and layout (LSL renderer only)

> Layout parameters (colors, fonts, sizes) are not yet transmitted to the server renderer. Server-side appearance is controlled by the server configuration.

| Key | Default | Description |
|-----|---------|-------------|
| `mainFontName` | `Junction` | Main font name |
| `mainFontSize` | `16` | Main font size in pixels |
| `hourFontName` | *(mainFontName)* | Hour marker font (falls back to `mainFontName`) |
| `hourFontSize` | `12` | Hour marker font size in pixels |
| `lineHeight` | `28` | Line height in pixels |
| `cellPadding` | `0` | Padding inside each cell in pixels |

### Behavior

| Key | Default | Description |
|-----|---------|-------------|
| `teleportMethod` | `dialog` | Teleport method: `dialog`, `teleport`, or `map` |
| `updateWarning` | `TRUE` | Show a warning when a script update is available |
| `sendSimInfo` | `FALSE` | Send simulator info to the aggregator with each request |

## Licence and copyright

(c) 2018-2026 Gudule Lapointe [gudule@speculoos.world](mailto:gudule@speculoos.world). Based on the work of Tom Frost [tomfrost@linkwater.org](mailto:tomfrost@linkwater.org).

Licence: GPLv3
