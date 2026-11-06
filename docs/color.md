# Colors

## Principle

A project's color is **computed from its name**, deterministically. The VS Code extension (JavaScript) and the app (Swift) do the same computation and get the same hex without passing it to each other, so a project always has the same color.

## Palettes

Instead of a continuous hue over 360°, the hash picks one of **5 fixed colors**. Two projects are therefore either clearly different or identical. A collision is easy to see and fixed with `colors.json`.

Two palettes, chosen in the app's menu (right-click on a light) and saved in `~/.cuelight/settings.json` (see ARCHITECTURE.md). Both have 5 colors, so switching palettes keeps each project's index; the hues of the two palettes don't match one to one.

| index | `vivid` (default) | `pastel` |
|---|---|---|
| 0 | `#F72585` | `#CDB4DB` |
| 1 | `#7209B7` | `#FFC8DD` |
| 2 | `#3A0CA3` | `#FFAFCC` |
| 3 | `#4361EE` | `#BDE0FE` |
| 4 | `#4CC9F0` | `#A2D2FF` |

Sources: [vivid](https://coolors.co/palette/f72585-7209b7-3a0ca3-4361ee-4cc9f0), [pastel](https://coolors.co/palette/cdb4db-ffc8dd-ffafcc-bde0fe-a2d2ff).

The tables are copied as is into `vscode-extension/extension.js` and `menubar-app/main.swift`. **Change all three together**, then recompute the test vectors.

Title bar text: dark `#1D1D22` when the color's relative luminance (WCAG) is above 0.4, white otherwise. So the text is white with `vivid` except on `#4CC9F0`, dark with `pastel`, and the rule also covers a color forced in `colors.json`. Inactive window: same color at 70% opacity, text at 60%.

## Algorithm

1. **Project name** = the name of the root folder open in VS Code (last path component), as is (case kept).
2. If `~/.cuelight/colors.json` has this name, use that color and stop.
3. `h = SHA-256(name as UTF-8)`.
4. `index = (h[0] << 24 | h[1] << 16 | h[2] << 8 | h[3]) mod 5` (unsigned integer, big-endian bytes).
5. Color = `PALETTES[palette][index]`, with `palette` read from `settings.json` (`vivid` by default).

## Test vectors

| Name | index | `vivid` | `pastel` |
|---|---|---|---|
| `my-app` | 1 | `#7209B7` | `#FFC8DD` |
| `api-server` | 0 | `#F72585` | `#CDB4DB` |
| `website` | 3 | `#4361EE` | `#BDE0FE` |
| `dotfiles` | 0 | `#F72585` | `#CDB4DB` |
| `Notes App` (space) | 1 | `#7209B7` | `#FFC8DD` |
| `café` (non-ASCII) | 4 | `#4CC9F0` | `#A2D2FF` |

`api-server` and `dotfiles` land on the same color: exactly the case `colors.json` fixes.

## Collisions

With 5 colors, two projects open at the same time share a color often (about 1 in 2 with 3 projects). The fix is `colors.json`. If it happens too often in practice, use larger palettes.
