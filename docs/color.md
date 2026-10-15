# Colors

## Principle

A project's color is **computed from its name**, deterministically. The VS Code extension (JavaScript) and the app (Swift) do the same computation and get the same hex without passing it to each other, so a project always has the same color.

## Palettes

Instead of a continuous hue over 360°, the hash picks one of **8 fixed colors**. Two projects are therefore either clearly different or identical. A collision is easy to see and fixed with `colors.json`.

Three palettes, chosen in the app's menu (right-click on a light) and saved in `~/.cuelight/settings.json` (see ARCHITECTURE.md). All three follow the same order of hues: switching palettes keeps each project's hue and only changes the shade.

| index | Hue | `vivid` | `soft` | `pastel` (default) |
|---|---|---|---|---|
| 0 | blue | `#2D5BE3` | `#4E6FAE` | `#9DBDF2` |
| 1 | green | `#13915F` | `#4E8B6B` | `#97D8B2` |
| 2 | red | `#D03A3A` | `#B5524F` | `#F2A6A0` |
| 3 | purple | `#7B3FE4` | `#7D62AE` | `#C6B0F2` |
| 4 | teal | `#0E8AA0` | `#3F8C99` | `#93D3DD` |
| 5 | pink | `#C93782` | `#A85A85` | `#F0ABCD` |
| 6 | orange | `#DD6B20` | `#C07A3E` | `#F6C28E` |
| 7 | lime | `#5E9E1E` | `#7F8C3F` | `#D2DE92` |

The tables are copied as is into `vscode-extension/extension.js` and `menubar-app/main.swift`. **Change all three together**, then recompute the test vectors.

Title bar text: dark `#1D1D22` when the color's relative luminance (WCAG) is above 0.4, white otherwise. So the text is dark with `pastel` and white with the other two, and the rule also covers a color forced in `colors.json`. Inactive window: same color at 70% opacity, text at 60%.

## Algorithm

1. **Project name** = the name of the root folder open in VS Code (last path component), as is (case kept).
2. If `~/.cuelight/colors.json` has this name, use that color and stop.
3. `h = SHA-256(name as UTF-8)`.
4. `index = (h[0] << 24 | h[1] << 16 | h[2] << 8 | h[3]) mod 8` (unsigned integer, big-endian bytes).
5. Color = `PALETTES[palette][index]`, with `palette` read from `settings.json` (`pastel` by default).

## Test vectors

| Name | index | `vivid` | `soft` | `pastel` |
|---|---|---|---|---|
| `my-app` | 4 | `#0E8AA0` | `#3F8C99` | `#93D3DD` |
| `api-server` | 3 | `#7B3FE4` | `#7D62AE` | `#C6B0F2` |
| `website` | 1 | `#13915F` | `#4E8B6B` | `#97D8B2` |
| `dotfiles` | 1 | `#13915F` | `#4E8B6B` | `#97D8B2` |
| `Notes App` (space) | 6 | `#DD6B20` | `#C07A3E` | `#F6C28E` |
| `café` (non-ASCII) | 4 | `#0E8AA0` | `#3F8C99` | `#93D3DD` |

`website` and `dotfiles` land on the same color: exactly the case `colors.json` fixes.

## Collisions

With 8 hues, two projects open at the same time share a color fairly often (about 1 in 3 with 3 projects). The fix is `colors.json`. If it happens too often in practice, move to 12 hues.
