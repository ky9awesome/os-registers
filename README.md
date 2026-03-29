# Registers

Named clipboard registers for macOS. Copy text to a lettered slot, paste it back from anywhere — no scrolling through history, no mouse required.

## Concept

macOS has one clipboard. If you're moving multiple pieces of text between windows, you end up in an endless copy-switch-paste-switch loop. Registers solves this by giving you 26 named slots (`a`–`z`) that persist across apps, reboots, and sessions.

The interaction mirrors `Cmd+C` / `Cmd+V`: press the chord to enter a mode, then press a letter to act on that register. Two keystrokes, direct access.

## In Practice

<video src="https://github.com/ky9awesome/os-registers/refs/heads/publish/demo.mp4" autoplay loop muted playsinline width="800"></video>

## Usage

### Copy to a register

1. Select text in any app
2. Press `Cmd+Shift+C`
3. Press a letter (`a`–`z`)

The selected text is saved to that register. A toast confirms: `Saved to [a]: "your text..."`

### Paste from a register

1. Position your cursor
2. Press `Cmd+Shift+V`
3. Press a letter (`a`–`z`)

The register's content is pasted at the cursor. If the register is empty, a toast says so and nothing is pasted.

### View all registers

Press `Cmd+Shift+R` to open the register viewer — a searchable list of all populated registers with content previews and timestamps. Select a row to paste it. The viewer also lets you clear individual registers or all registers at once.

### Cancel

Press `Escape` (or any non-letter key) during a copy or paste prompt to cancel. The mode also auto-cancels after 3 seconds of inactivity.

## Installation

Requires [Hammerspoon](https://www.hammerspoon.org).

1. Clone or symlink this repo's `os-registers/` directory into your Hammerspoon config folder:

   ```bash
   ln -s /path/to/os-registers/os-registers ~/.hammerspoon/os-registers
   ```

2. Add one line to `~/.hammerspoon/init.lua`:

   ```lua
   require("os-registers")
   ```

3. Reload Hammerspoon (menu bar icon → Reload Config).

You should see `[os-registers] Loaded 0 register(s)...` in the Hammerspoon console.

Register data is stored at `~/.hammerspoon/registers.json` and persists across reloads and reboots.

## What to test

The prototype exists to validate whether the two-chord interaction model feels natural before investing in a native app. When using it, pay attention to:

- Does the 3-second modal timeout feel right, or is it too short/long?
- Does `Cmd+Shift+V` clobbering "Paste and Match Style" actually bother you in practice?
- Is the register viewer (`Cmd+Shift+R`) useful, or do you rarely reach for it?
- Does the 100ms delay after `Cmd+C` ever feel laggy or miss content in fast-switching scenarios?

If something feels off, the Lua is easy to iterate on. If the model validates, the next step is a native Swift/AppKit app — which resolves the `Cmd+Shift+V` conflict, removes the `Cmd+C` simulation side-effect, and adds full-screen app support and proper distribution.

## Notes

- `Cmd+Shift+V` is intercepted globally, which overrides "Paste and Match Style" in text editors. This is a known trade-off of the Hammerspoon prototype.
- Copy mode simulates `Cmd+C` internally to capture your selection, so the system clipboard is overwritten on each copy-to-register operation.
- This is a Hammerspoon prototype. A native Swift/AppKit implementation is planned if the interaction model proves out.
