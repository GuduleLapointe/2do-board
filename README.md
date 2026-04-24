# 2DO board

In-world teleporter board for 2DO events server.

- Get the latest version in-world at Speculoos Lab: [speculoos.world:8002/Lab](hop://speculoos.world:8002/Lab/)
- or from [Kitely Market](https://www.kitely.com/market/product/50129545)

## Features

- Fetches upcoming events from [2do.directory](https://2do.directory) (or a self-hosted aggregator)
- Touch-to-teleport: touching an event row teleports you to the event location
- Two rendering modes:
  - **LSL renderer** (default): client-side text rendering via `osDrawText` / `osDynamicTextureDataBlendFace`
  - **PNG renderer** (`renderer=png`): server-rendered board image applied via `osSetDynamicTextureURLBlendFace`
- Auto-refreshes at a configurable interval
- Applies texture to specific prim faces, with automatic ratio detection for non-square faces

## Installation from sources

- Put the content of `2DO board.lsl` in a script named "2DO board"
- Put the content of `2DO Read me` in a notecard named "2DO Read me"
- Put the content of one of the theme files in a notecard named "Configuration"
- Let the magic happen

## Configuration

Settings are read from the "Configuration" notecard inside the prim. Keys are case-insensitive and accept both `camelCase` and `ALL_CAPS_UNDERSCORE` forms.

| Key | Default | Description |
|-----|---------|-------------|
| `eventsURL` | `https://2do.directory/events/events.php` | Events source URL |
| `renderer` | *(empty)* | Set to `png` for server-side PNG rendering; leave empty for LSL renderer |
| `ratio` | `0` | Face aspect ratio (width/height); `0` = auto-detect from prim scale |
| `ratioCap` | `0.25` | Skip faces whose ratio is outside `[ratioCap, 1/ratioCap]` (e.g. extreme side faces) |
| `activeSides` | `0,1,2,3,4,5` | Comma-separated list of prim faces to apply the texture to |
| `textureWidth` | `512` | Texture resolution (width in pixels) |
| `textureHeight` | `512` | Texture resolution (height in pixels) |
| `refreshTime` | `1800` | Refresh interval in seconds |
| `bannerURL` | *(2do logo)* | URL of the banner/logo image shown at the bottom |
| `bannerHeight` | `90` | Banner area height in pixels (LSL renderer) |
| `backgroundColor` | `ff000000` | Background color as ARGB hex (LSL renderer only) |
| `fontColor` | `ff33ff33` | Text color as ARGB hex (LSL renderer only) |
| `mainFontName` | `Junction` | Main font name (LSL renderer only) |
| `mainFontSize` | `16` | Main font size in pixels (LSL renderer only) |
| `lineHeight` | `28` | Line height in pixels (LSL renderer only) |
| `showPastEvents` | `FALSE` | Include events that have already ended |
| `updateWarning` | `TRUE` | Show a warning when a script update is available |
| `sendSimInfo` | `FALSE` | Send simulator info to the aggregator with each request |

## Licence and copyright

(c) 2018-2026 Gudule Lapointe [gudule@speculoos.world](mailto:gudule@speculoos.world). Based on the work of Tom Frost [tomfrost@linkwater.org](mailto:tomfrost@linkwater.org).

Licence: GPLv3
