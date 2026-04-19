# ChatType HUD Visual Spec

This spec mirrors the HUD implementation currently shipped in `dist/ChatType.app` and is intended to be copied into the Figma `HUD` board once the Starter-plan MCP limit resets.

## Core Shell

- Container: graphite pill
- Processing / success size: `220 x 56`
- Recording size: `256 x 56`
- Error size: `320 x 56`
- Corner radius: `18`
- Border: `1px`, mist at `8%` opacity
- Shadow: short, low-contrast black shadow
- Layout:
  - leading visual width: `76`
  - leading visual height: `30`
  - leading inset: `14`
  - text gap: `10`
  - trailing inset: `16`
  - trailing timer reserve: `42`
  - close control: `12 x 12`, inset from top-left by `10`

## Color Tokens

- Graphite: `#171C26` at `96%` opacity
- Mist: `#F0F5FB`
- Mist Muted: `#C7D1E0`
- Ice Blue: `#7AC7FF`
- Success: `#59D69E`
- Amber: `#FFBF52`
- Error: `#FF7375`

## Typography

- Title:
  - size: `14`
  - weight: semibold
  - color: Mist
- Detail:
  - size: `11`
  - weight: medium
  - color: Mist Muted

## Recording

- Title: `Listening`
- Cancel affordances:
  - `ESC` cancels the current session
  - a red macOS-style close control sits at the top-left of the pill
- Leading visual: 9 thin waveform bars
- Bar count: `9`
- Bar spacing: `4`
- Minimum bar height: `6`
- Trailing timer:
  - visible only while recording
  - format `mm:ss`
  - uses compact monospaced digits on the right edge
- Shape rule:
  - center bar should be the tallest
  - bars fall off symmetrically toward the edges
  - outer bars stay visibly active, never collapse to dots
- Color rule:
  - center bars blend toward Ice Blue
  - outer bars remain mist-toned with lower emphasis

Reference profile:

- `[0.22, 0.34, 0.48, 0.72, 1.00, 0.74, 0.50, 0.34, 0.22]`

## Processing

- Title: `Processing`
- Cancel affordances remain active:
  - `ESC` cancels the current transcription
  - the close control still dismisses the in-flight session
- Timer is hidden in this state
- Leading visual: same 9-bar skeleton as recording
- Animation rule:
  - do not pulse the entire group uniformly
  - send a traveling ridge from left to right across the 9 bars
  - keep the center-weighted contour underneath the moving ridge

Reference frames:

- frame A: `[0.18, 0.24, 0.38, 0.62, 0.88, 0.56, 0.34, 0.22, 0.18]`
- frame B: `[0.18, 0.22, 0.30, 0.48, 0.68, 0.90, 0.58, 0.32, 0.20]`
- frame C: `[0.18, 0.20, 0.24, 0.34, 0.52, 0.72, 0.92, 0.54, 0.28]`

## Success

- Title: `Pasted`
- No cancel affordance in this state
- Leading visual: rounded badge inside the same pill system
- Badge size: `64 x 36`
- Badge radius: `18`
- Fill: Success at low opacity
- Border: Success at medium opacity
- Icon: checkmark

## Clipboard Fallback

- Title: `Copied`
- No cancel affordance in this state
- Leading visual: same badge container as success
- Fill: Amber at low opacity
- Border: Amber at medium opacity
- Icon: clipboard/document glyph

## Error

- Title: `Error`
- No cancel affordance in this state
- Detail text is visible
- Leading visual: same badge container as success/copy
- Fill: Error at low opacity
- Border: Error at medium opacity
- Icon: exclamation mark

## Figma Board Layout

When the MCP quota resets, the `HUD` board in Figma should contain:

1. Heading block
   - eyebrow: `HUD STATES`
   - title: `Nine-bar rhythm inside the same graphite pill`
   - subtitle explaining shared skeleton + traveling processing ridge

2. Top row
   - `Recording` card with one HUD pill
   - `Processing` card with three stacked reference frames

3. Bottom row
   - `Completion States` card with `Pasted` and `Copied`
   - `Error` card with one error pill

4. Rules block
   - 9 bars, never return to the older dense 12/16-bar block
   - Ice Blue stays concentrated on the active center bars
   - Success/copy/error remain inside the same branded pill architecture
