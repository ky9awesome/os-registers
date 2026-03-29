-- os-registers/init.lua
-- Named clipboard registers for macOS via Hammerspoon
-- Load with: require("os-registers") in ~/.hammerspoon/init.lua
--
-- Copy flow: simulates Cmd+C to capture the current selection in the
-- frontmost app, then reads the clipboard. The system clipboard is
-- overwritten on every copy-to-register operation.

------------------------------------------------------------------------
-- 1. Constants
------------------------------------------------------------------------
local REGISTERS_PATH = os.getenv("HOME") .. "/.hammerspoon/registers.json"
local TOAST_DURATION = 1.5  -- seconds
local MODAL_TIMEOUT  = 3.0  -- seconds before auto-cancel
local PREVIEW_LEN    = 40   -- max characters in toast preview

-- Non-letter keys that cancel an active modal.
-- Note: exotic keys (F-keys, arrow keys, media keys) are not listed and
-- will silently pass through without cancelling -- prototype limitation.
local CANCEL_KEYS = {
    "return", "space", "tab", "delete", "forwarddelete",
    "0","1","2","3","4","5","6","7","8","9",
    "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/", "`",
}

------------------------------------------------------------------------
-- 2. State
------------------------------------------------------------------------
local registers     = {}   -- { a = { content = "...", timestamp = 1234567 }, ... }
local activeModal   = nil  -- currently open hs.hotkey.modal, or nil
local timeoutTimer  = nil  -- hs.timer handle, or nil
local activeAlertId = nil  -- alert UUID for replace-not-stack behavior
local chooser       = nil  -- hs.chooser instance, rebuilt on each open

------------------------------------------------------------------------
-- 3. Persistence
------------------------------------------------------------------------
local function loadRegisters()
    local f = io.open(REGISTERS_PATH, "r")
    if not f then
        print("[os-registers] No registers file found, starting fresh: " .. REGISTERS_PATH)
        return
    end
    local raw = f:read("*a")
    f:close()
    local ok, decoded = pcall(hs.json.decode, raw)
    if ok and type(decoded) == "table" then
        registers = decoded
    else
        print("[os-registers] WARNING: Could not decode registers.json, starting fresh")
    end
end

local function saveRegisters()
    local ok, encoded = pcall(hs.json.encode, registers, true)  -- true = pretty-print
    if not ok then
        print("[os-registers] ERROR: Could not encode registers to JSON")
        return
    end
    if #encoded > 1024 * 1024 then
        print("[os-registers] WARNING: registers.json exceeds 1MB (" .. #encoded .. " bytes)")
    end
    local f = io.open(REGISTERS_PATH, "w")
    if not f then
        print("[os-registers] ERROR: Cannot write to " .. REGISTERS_PATH)
        return
    end
    f:write(encoded)
    f:close()
end

------------------------------------------------------------------------
-- 4. Utility Functions
------------------------------------------------------------------------

-- Truncate and normalize text for previews in toasts and the viewer.
-- Collapses whitespace runs to single spaces, strips leading/trailing space.
local function makePreview(text)
    if not text then return "" end
    local s = text:gsub("%s+", " "):match("^%s*(.-)%s*$")
    if #s > PREVIEW_LEN then
        s = s:sub(1, PREVIEW_LEN) .. "..."
    end
    return s
end

-- Human-readable relative time from a Unix epoch number.
-- Timestamps are stored as integers (os.time()) to avoid timezone bugs
-- that come with parsing ISO 8601 strings in Lua.
local function relativeTime(epoch)
    if not epoch or type(epoch) ~= "number" then return "unknown" end
    local diff = os.time() - epoch
    if diff < 60         then return "just now"
    elseif diff < 3600   then return math.floor(diff / 60) .. "m ago"
    elseif diff < 86400  then return math.floor(diff / 3600) .. "h ago"
    elseif diff < 172800 then return "yesterday"
    else return math.floor(diff / 86400) .. "d ago"
    end
end

------------------------------------------------------------------------
-- 5. Toast Helper
------------------------------------------------------------------------

-- Show a toast, replacing any currently visible one (no stacking).
-- hs.alert.defaultStyle.atScreenEdge = 2 is set in the parent init.lua,
-- so toasts appear at the top edge of the screen automatically.
local function toast(msg)
    if activeAlertId then
        hs.alert.closeSpecific(activeAlertId)
        activeAlertId = nil
    end
    activeAlertId = hs.alert.show(msg, TOAST_DURATION)
end

------------------------------------------------------------------------
-- 6. Modal Lifecycle Helpers
------------------------------------------------------------------------

local function cancelModal(reason)
    if timeoutTimer then
        timeoutTimer:stop()
        timeoutTimer = nil
    end
    if activeModal then
        activeModal:exit()
        activeModal = nil
    end
    if reason then
        toast(reason)
    end
end

-- Bind a–z (plus Shift+a–z) in a modal. The handler always receives a
-- lowercase letter, so "A" and "a" address the same register.
local function bindLetters(modal, handler)
    for i = 0, 25 do
        local letter = string.char(string.byte("a") + i)
        modal:bind("",        letter, function() handler(letter) end)
        modal:bind({"shift"}, letter, function() handler(letter) end)
    end
end

-- Bind common non-letter keys so they cancel the modal.
local function bindCancelKeys(modal)
    modal:bind("", "escape", function() cancelModal("Cancelled") end)
    for _, k in ipairs(CANCEL_KEYS) do
        modal:bind("", k, function() cancelModal("Cancelled") end)
    end
end

local function startTimeout()
    timeoutTimer = hs.timer.doAfter(MODAL_TIMEOUT, function()
        cancelModal("Cancelled (timeout)")
    end)
end

------------------------------------------------------------------------
-- 7. Copy Mode  (Cmd+Shift+C → letter)
------------------------------------------------------------------------

local function enterCopyMode()
    cancelModal(nil)  -- dismiss any existing modal first

    local m = hs.hotkey.modal.new()
    activeModal = m

    toast("Copy to register: _")

    bindLetters(m, function(letter)
        cancelModal(nil)  -- exit modal before sending keystrokes

        -- Simulate Cmd+C so the target app copies its current selection.
        -- The modal has already exited, so this goes to the frontmost app.
        hs.eventtap.keyStroke({"cmd"}, "c")

        -- Wait 100ms for the target app to update the clipboard.
        hs.timer.doAfter(0.1, function()
            local content = hs.pasteboard.getContents()
            if not content then
                local types = hs.pasteboard.contentTypes()
                if types and #types > 0 then
                    toast("Register only supports plain text")
                else
                    toast("Nothing to copy")
                end
                return
            end
            if content == "" then
                toast("Nothing to copy")
                return
            end
            registers[letter] = {
                content   = content,
                timestamp = os.time(),
            }
            saveRegisters()
            toast('Saved to [' .. letter .. ']: "' .. makePreview(content) .. '"')
        end)
    end)

    bindCancelKeys(m)
    startTimeout()
    m:enter()
end

------------------------------------------------------------------------
-- 8. Paste Mode  (Cmd+Shift+V → letter)
------------------------------------------------------------------------

local function enterPasteMode()
    cancelModal(nil)

    local m = hs.hotkey.modal.new()
    activeModal = m

    toast("Paste from register: _")

    bindLetters(m, function(letter)
        cancelModal(nil)

        local entry = registers[letter]
        if not entry or not entry.content or entry.content == "" then
            toast("Register [" .. letter .. "] is empty")
            return
        end

        hs.pasteboard.setContents(entry.content)
        -- Small delay so the target app fully regains focus after modal exit.
        hs.timer.doAfter(0.05, function()
            hs.eventtap.keyStroke({"cmd"}, "v")
        end)
        toast('Pasted from [' .. letter .. ']: "' .. makePreview(entry.content) .. '"')
    end)

    bindCancelKeys(m)
    startTimeout()
    m:enter()
end

------------------------------------------------------------------------
-- 9. Register Viewer  (Cmd+Shift+R → hs.chooser)
------------------------------------------------------------------------

local function buildChooserChoices()
    local choices = {}

    -- Collect and sort populated register keys
    local letters = {}
    for k in pairs(registers) do
        if type(k) == "string" and #k == 1 and k:match("[a-z]") then
            table.insert(letters, k)
        end
    end
    table.sort(letters)

    -- Paste rows (one per populated register)
    for _, letter in ipairs(letters) do
        local entry = registers[letter]
        if entry and entry.content and entry.content ~= "" then
            table.insert(choices, {
                text    = "[" .. letter .. "]  " .. makePreview(entry.content),
                subText = relativeTime(entry.timestamp),
                action  = "paste",
                regKey  = letter,
            })
        end
    end

    if #choices == 0 then
        table.insert(choices, {
            text    = "No registers saved",
            subText = "Use Cmd+Shift+C → letter to copy text to a register",
            action  = "none",
        })
        return choices
    end

    -- Visual separator
    table.insert(choices, {
        text    = "────────────────────────────────",
        subText = "Actions",
        action  = "none",
    })

    -- Clear-individual rows
    for _, letter in ipairs(letters) do
        table.insert(choices, {
            text    = "Clear register [" .. letter .. "]",
            subText = "Remove this register's content",
            action  = "clear",
            regKey  = letter,
        })
    end

    -- Clear-all row
    table.insert(choices, {
        text    = "Clear all registers",
        subText = string.format("Remove all %d saved registers", #letters),
        action  = "clearAll",
    })

    return choices
end

local function openViewer()
    cancelModal(nil)  -- dismiss any active copy/paste modal

    -- Rebuild chooser each time so it reflects current register state
    if chooser then
        chooser:delete()
        chooser = nil
    end

    chooser = hs.chooser.new(function(choice)
        chooser = nil
        if not choice then return end  -- dismissed with Escape

        if choice.action == "paste" then
            local entry = registers[choice.regKey]
            if not entry or not entry.content or entry.content == "" then
                toast("Register [" .. choice.regKey .. "] is empty")
                return
            end
            hs.pasteboard.setContents(entry.content)
            -- Delay paste to let chooser fully dismiss and target app regain focus
            hs.timer.doAfter(0.1, function()
                hs.eventtap.keyStroke({"cmd"}, "v")
            end)
            toast('Pasted from [' .. choice.regKey .. ']: "' .. makePreview(entry.content) .. '"')

        elseif choice.action == "clear" then
            registers[choice.regKey] = nil
            saveRegisters()
            toast("Cleared register [" .. choice.regKey .. "]")

        elseif choice.action == "clearAll" then
            -- No confirmation dialog: hs.chooser cannot nest dialogs (prototype limitation)
            local count = 0
            for _ in pairs(registers) do count = count + 1 end
            registers = {}
            saveRegisters()
            toast("All registers cleared (" .. count .. " removed)")
        end
        -- action == "none" (separator / empty-state row) is a no-op
    end)

    chooser:choices(buildChooserChoices())
    chooser:placeholderText("Select a register to paste, or search...")
    chooser:show()
end

------------------------------------------------------------------------
-- 10. Hotkey Registration
------------------------------------------------------------------------
-- Cmd+Shift+C and Cmd+Shift+V are intercepted globally. This overrides
-- app-specific uses such as "Paste and Match Style" (Cmd+Shift+V) in
-- text editors — an intentional prototype trade-off.
hs.hotkey.bind({"cmd", "shift"}, "c", enterCopyMode)
hs.hotkey.bind({"cmd", "shift"}, "v", enterPasteMode)
hs.hotkey.bind({"cmd", "shift"}, "r", openViewer)

------------------------------------------------------------------------
-- 11. Initialization
------------------------------------------------------------------------
loadRegisters()

local function countRegisters()
    local n = 0
    for _ in pairs(registers) do n = n + 1 end
    return n
end
print("[os-registers] Loaded " .. countRegisters() .. " register(s) from " .. REGISTERS_PATH)
