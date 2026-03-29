**Registers**

System-Level Named Clipboard Registers for macOS

  ------------------ ----------------------------------------------------
  **Field**          **Value**

  Version            0.1 (MVP Spec)

  Date               March 29, 2026

  Author             kk

  Status             Draft

  Target Platform    macOS 13+ (Ventura and later)
  ------------------ ----------------------------------------------------

1\. Overview

Registers is a macOS utility that provides named clipboard slots
(registers), allowing users to copy text to and paste text from specific
keyboard-designated storage locations. It extends the familiar Cmd+C /
Cmd+V interaction model by adding a register selection step, giving
users instant random access to multiple saved snippets without scrolling
through clipboard history.

Problem Statement

Every major operating system provides a single clipboard. Users who
regularly work with multiple pieces of text---developers, writers, data
entry workers, customer support agents, anyone filling forms or moving
content between applications---are forced into a tedious cycle of
copy-switch-paste-switch-copy. Existing clipboard managers address this
with searchable history lists, but that model still requires
interrupting your flow to visually locate and select the right item.
Named registers offer a fundamentally different interaction: direct
access by key, with no searching or scrolling required.

Design Principles

- Zero learning curve: keybindings mirror the Cmd+C / Cmd+V convention
  that every macOS user already knows.

- Instant feedback: every action produces a brief, non-intrusive toast
  notification confirming what happened.

- Persistence: registers survive application restarts, system reboots,
  and macOS updates.

- Minimal footprint: no menu bar icon by default, no dock icon, no
  background browser or Electron runtime.

2\. Core Interaction Model

2.1 Keybindings

All interactions use a two-step sequential chord. The first keypress
enters a modal state; the second keypress selects the register.

  ---------------- ------------------ ------------------- ----------------
  **Action**       **Step 1 (Enter    **Step 2 (Select    **Example**
                   Mode)**            Register)**         

  Copy to register Cmd+Shift+C        Any letter a--z     Cmd+Shift+C → a

  Paste from       Cmd+Shift+V        Any letter a--z     Cmd+Shift+V → j
  register                                                

  View all         Cmd+Shift+R        --- (opens overlay) Cmd+Shift+R
  registers                                               
  ---------------- ------------------ ------------------- ----------------

2.2 Interaction Flow: Copy

1.  User selects text in any application.

2.  User presses Cmd+Shift+C.

3.  A small toast appears near the cursor or screen center: "Copy to
    register: \_"

4.  User presses a letter key (e.g., "a").

5.  The currently selected text (or current clipboard contents if no
    selection is active) is saved to register "a."

6.  Toast updates to confirm: "Saved to register a" with a preview of
    the stored text (truncated to \~40 characters).

7.  Modal state exits. User continues working.

2.3 Interaction Flow: Paste

1.  User positions cursor where they want to paste.

2.  User presses Cmd+Shift+V.

3.  A small toast appears: "Paste from register: \_"

4.  User presses a letter key (e.g., "a").

5.  The contents of register "a" are inserted at the cursor position
    (via pasteboard injection, simulating a standard paste).

6.  Toast confirms: "Pasted from register a" with a preview of the
    pasted text.

7.  If the register is empty, toast reads: "Register a is empty." No
    paste action occurs.

2.4 Interaction Flow: Cancel

If the user presses Escape, or any non-letter key, or if no key is
pressed within 3 seconds, the modal state exits with no action. A brief
toast confirms: "Cancelled."

3\. Register Viewer Overlay

Pressing Cmd+Shift+R opens a floating overlay panel showing all
populated registers. The overlay is non-modal (the user can click away
to dismiss it) and serves as a quick reference.

3.1 Layout

- Centered on screen, approximately 480px wide, max height 70% of screen
  height, scrollable if needed.

- Each row displays: register letter (bold, monospaced), a truncated
  preview of stored text (\~60 characters), and a relative timestamp
  ("2m ago," "yesterday," etc.).

- Empty registers are hidden by default. A "Show all" toggle reveals all
  26 slots.

- Clicking a row copies that register's contents to the system clipboard
  and dismisses the overlay.

3.2 Keyboard Navigation

- Pressing a letter key while the overlay is open pastes from that
  register (same as Cmd+Shift+V → letter) and dismisses the overlay.

- Escape or clicking outside dismisses the overlay with no action.

- Up/Down arrow keys move a highlight cursor; Enter pastes the
  highlighted register.

4\. Toast Notifications

Every user-initiated event produces a toast notification. Toasts are the
primary feedback mechanism and must feel instant, unobtrusive, and
informative.

4.1 Toast Behavior

  ------------------ ----------------------------------------------------
  **Property**       **Value**

  Position           Top-right of screen (below menu bar, avoiding notch
                     on MacBooks)

  Duration           1.5 seconds (auto-dismiss)

  Animation          Slide in from right, fade out

  Stacking           If a new toast fires while one is visible, replace
                     (do not stack)

  Interaction        Clicking a toast dismisses it immediately

  Style              Rounded rect, subtle drop shadow, semi-transparent
                     background, system font
  ------------------ ----------------------------------------------------

4.2 Toast Content by Event

  ------------------------ ----------------------------------------------
  **Event**                **Toast Content**

  Mode entered (copy)      Copy to register: \_

  Mode entered (paste)     Paste from register: \_

  Copy succeeded           Saved to register \[x\]: \"\[preview\...\]\"​

  Paste succeeded          Pasted from register \[x\]:
                           \"\[preview\...\]\"​

  Paste from empty         Register \[x\] is empty
  register                 

  Register cleared         Cleared register \[x\]

  All registers cleared    All registers cleared

  Mode cancelled           Cancelled

  Mode timed out           Cancelled (timeout)
  ------------------------ ----------------------------------------------

Preview text is truncated to 40 characters with an ellipsis if longer.
Special characters and newlines are collapsed to spaces in the preview.

5\. Data Model & Persistence

5.1 Storage

- Registers are stored as a JSON file at \~/Library/Application
  Support/Registers/registers.json.

- The file is written on every copy or clear operation. Writes are
  atomic (write to temp file, then rename) to prevent corruption.

- The file is loaded into memory on application launch. All read
  operations use the in-memory store.

5.2 Schema

Each register entry contains:

  --------------- ------------------ -------------------------------------
  **Field**       **Type**           **Description**

  key             string (a--z)      The register identifier

  content         string             The stored text

  timestamp       ISO 8601 string    When the content was saved
  --------------- ------------------ -------------------------------------

Example:

{ \"a\": { \"content\": \"Hello world\", \"timestamp\":
\"2026-03-29T14:22:00Z\" }, \"j\": { \"content\": \"SELECT \* FROM
users;\", \"timestamp\": \"2026-03-29T14:20:00Z\" } }

5.3 Content Type

MVP supports plain text only. Rich content (images, formatted text, file
references) is out of scope. If the clipboard contains non-text data
when the user attempts to copy to a register, the toast should read:
"Register only supports plain text."

5.4 Limits

- 26 registers (a--z). No uppercase distinction---"A" and "a" refer to
  the same register.

- No per-register size limit in MVP, but total JSON file size should be
  monitored. If the file exceeds 10 MB, the oldest registers (by
  timestamp) should be flagged in the viewer overlay but not
  auto-deleted.

6\. Register Management

6.1 Clear a Single Register

In the register viewer overlay, each populated row has a small "×"
button. Clicking it clears that register and shows a confirmation toast:
"Cleared register \[x\]."

6.2 Clear All Registers

The register viewer overlay has a "Clear All" button at the bottom.
Clicking it prompts a confirmation ("Clear all 8 registers?" with Cancel
/ Clear All buttons). On confirmation, all registers are emptied and the
toast reads: "All registers cleared."

7\. Edge Cases & Error Handling

  ------------------------ ----------------------------------------------
  **Scenario**             **Behavior**

  No text selected and     Toast: "Nothing to copy." No register
  clipboard is empty on    modified.
  copy                     

  Paste into a read-only   The paste is attempted via standard pasteboard
  field or context         injection. If the target app ignores it, no
                           error from Registers is expected. Standard OS
                           behavior applies.

  Rapid repeated           Each invocation cancels any pending modal
  invocations              state and starts fresh.

  App crashes or           Atomic file writes (temp + rename) prevent
  force-quit during write  JSON corruption. On next launch, the last
                           successfully written state is loaded.

  Register file is         App recreates an empty registers.json on next
  manually deleted         write. In-memory state is unaffected until
                           restart.

  Multiple displays        Toast appears on the display containing the
                           currently focused window.

  Full-screen apps         Toasts and the register viewer overlay must
                           render above full-screen applications (window
                           level above kCGMainMenuWindowLevel).
  ------------------------ ----------------------------------------------

8\. Hammerspoon Prototype Scope

The initial prototype will be implemented as a Hammerspoon module (Lua)
to validate the interaction model before investing in a native app
build. The prototype should implement:

- Copy and paste flows with Cmd+Shift+C / Cmd+Shift+V sequential chords
  (via hs.hotkey.modal).

- Toast notifications using hs.alert.show() or a custom hs.canvas-based
  toast.

- JSON persistence to \~/.hammerspoon/registers.json.

- Basic register viewer overlay using hs.chooser or hs.canvas.

The prototype does not need to implement: multi-display awareness,
full-screen overlay rendering, atomic file writes, or polished UI
styling. These are native app concerns.

9\. Native App Requirements (Post-Prototype)

If the prototype validates the interaction model, the native app should
be built as a Swift/AppKit application distributed outside the Mac App
Store (the app requires Accessibility permissions for global hotkeys and
pasteboard injection, which are restricted in sandboxed App Store
builds).

9.1 Technical Requirements

- Global hotkey registration via CGEvent taps or the Accessibility API.

- Pasteboard read/write via NSPasteboard.

- Paste injection via CGEvent (simulating Cmd+V after writing to the
  pasteboard).

- Overlay window at NSStatusWindowLevel or higher.

- No Dock icon (LSUIElement = true in Info.plist).

- Optional menu bar icon (user-configurable, off by default).

- Launch at Login support (via SMAppService on macOS 13+).

- Accessibility permission prompt on first launch.

9.2 Distribution

- Notarized and signed for Gatekeeper.

- Distributed via direct download (DMG) and optionally Homebrew Cask.

- Auto-update mechanism (Sparkle framework or equivalent).

10\. Future Considerations (Out of MVP Scope)

The following features are explicitly out of scope for the MVP and
prototype but are worth considering for future versions:

- Rich content support (images, formatted text, file references).

- Register groups or namespaces (e.g., work vs. personal).

- Sync across devices via iCloud or a similar mechanism.

- Customizable keybindings.

- Snippet expansion (registers as text expander templates with
  variables).

- CLI interface (e.g., "registers get a" from the terminal).

- Integration with Raycast, Alfred, or Spotlight.
