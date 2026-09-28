--[[
    sl_ui/client/bridge.lua — the ONE NUI bridge.

    Lua side of the React app. Features call the exports here; nothing else in the
    framework ever touches SendNUIMessage / SetNuiFocus / RegisterNUICallback.

    React listens to messages as { action, data } (see web/src/hooks/useNuiEvent.ts)
    and POSTs back to callbacks via fetchNui (web/src/lib/fetchNui.ts).
]]

local focused = false

-- The React app posts 'uiReady' once it has mounted and its window 'message'
-- listeners are attached. Messages sent BEFORE that — e.g. an 'open' fired the instant
-- the player connects, before the NUI iframe finished loading React — would otherwise
-- be silently dropped (which made the character screen never appear). So we QUEUE
-- important one-shot messages until the NUI is ready, then flush them in order.
-- 'hudUpdate' is NOT queued: the HUD loop re-sends it every 500ms, so a dropped early
-- one is harmless and we avoid a backlog of stale HUD frames.
local nuiReady = false
local pending = {}

-- Send a typed message to the React app (or queue it until the NUI is ready).
local function send(action, data)
    if nuiReady then
        SendNUIMessage({ action = action, data = data })
    elseif action ~= 'hudUpdate' then
        pending[#pending + 1] = { action = action, data = data }
    end
end

-- ── public exports (the only NUI entrypoints for the whole framework) ─────────

-- While a "keep input" screen (a menu) is open the player can still MOVE / DRIVE / FLY / JUMP:
-- the game keeps input (SetNuiFocusKeepInput) and we BLACKLIST only the controls that would leak
-- and conflict (chat, pause/ESC, attack, weapon cycling) — every movement control (on foot AND in
-- a vehicle AND aircraft) stays enabled, while the NUI keyboard drives the menu.
local keepInput = false
local guardActive = false

local SUPPRESS = {
    199, 200,                 -- pause / ESC (the NUI handles ESC = back)
    245, 246,                 -- text chat (so Enter/T don't open chat)
    24, 25, 257,              -- attack / aim
    263, 264, 140, 141, 142,  -- melee
    37, 47,                   -- weapon wheel / detonate
    14, 15, 16, 17,           -- weapon select (scroll / cycle)
    45,                       -- reload
    27,                       -- phone
    44,                       -- cover
}

local function startInputGuard()
    if guardActive then return end
    guardActive = true
    CreateThread(function()
        while focused and keepInput do
            for i = 1, #SUPPRESS do DisableControlAction(0, SUPPRESS[i], true) end
            Wait(0)
        end
        guardActive = false
    end)
end

-- Open an interactive screen. `allowMove` = keep the player able to walk / jump / look (menus,
-- keyboard-driven, no cursor); omitted/false = a modal that takes full focus + cursor
-- (charselect, charcreate, the numeric input).
local function openScreen(screen, data, allowMove)
    focused = true
    keepInput = allowMove and true or false
    SetNuiFocus(true, not keepInput)      -- cursor only for modals; menus are keyboard-driven
    SetNuiFocusKeepInput(keepInput)
    if keepInput then startInputGuard() end
    send('open', { screen = screen, payload = data })
end
exports('open', openScreen)

-- Close every screen and hand focus + control fully back to the game.
local function closeUI()
    focused = false
    keepInput = false
    SetNuiFocusKeepInput(false)
    SetNuiFocus(false, false)
    send('closeAll', {})
end
exports('close', closeUI)

-- Fire-and-forget toast. No focus change.
exports('notify', function(kind, message)
    send('notify', { kind = kind or 'info', message = message or '' })
end)

-- Push HUD values to the React HUD.
exports('hud', function(data)
    send('hudUpdate', data)
end)

-- Open the Liquid Glass list menu (Menu V layout). Grabs focus like any screen.
--   menu = { id, title, subtitle?, items = { { id, label, icon?, value?, description?, kind?, disabled? }, ... } }
-- The selected item / close come back as 'sl_ui:nui' events 'menu:select' {menuId,itemId} / 'menu:close' {menuId}.
exports('openMenu', function(menu)
    openScreen('menu', menu, true)  -- allowMove: walk / jump / look while the menu is open
end)

-- Open the Liquid Glass numeric input prompt (companion to the menu).
--   spec = { id, title, label?, description?, placeholder?, confirmLabel? }
-- Result comes back as 'sl_ui:nui' events 'input:submit' {id,value} / 'input:cancel' {id}.
exports('openInput', function(spec)
    openScreen('input', spec)
end)

-- Open the drag&drop inventory grid (modal: cursor + no movement, needs the mouse).
--   data = { player = {items,weight,maxWeight,slots}, container? = {...,id,label}, accent? }
-- Ops come back as 'sl_ui:nui' events: 'inv:move' / 'inv:use' / 'inv:drop' / 'inv:give' / 'inv:close'.
exports('openInventory', function(data)
    openScreen('inventory', data)  -- modal (allowMove omitted) -> cursor for drag&drop
end)

-- Push fresh inventory state to the open grid WITHOUT re-focusing (after each op).
exports('updateInventory', function(data)
    send('inventoryUpdate', data)
end)

-- React signals it has mounted (window 'message' listeners attached). Flush any
-- one-shot messages that were sent too early so they are never lost.
RegisterNUICallback('uiReady', function(_, cb)
    nuiReady = true
    for _, m in ipairs(pending) do
        SendNUIMessage({ action = m.action, data = m.data })
    end
    pending = {}
    cb({ ok = true })
end)

-- React requests a close (Escape / a Close button) -> release focus.
RegisterNUICallback('ui:close', function(_, cb)
    closeUI()
    cb({ ok = true })
end)

-- Generic callback bridge: React posts fetchNui('dispatch', { event, data }); any
-- feature resource listens via AddEventHandler('sl_ui:nui', function(event, data) end).
-- Keeps sl_ui feature-agnostic — it never needs to know about identity/banking/etc.
RegisterNUICallback('dispatch', function(body, cb)
    local event = body and body.event
    local data = (body and body.data) or {}
    if event then
        TriggerEvent('sl_ui:nui', event, data)
    end
    cb({ ok = true })
end)

-- Safety: if the resource stops while focused, don't leave the player with a
-- stuck cursor and locked controls.
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and focused then
        SetNuiFocusKeepInput(false)
        SetNuiFocus(false, false)
    end
end)

-- ── HUD feed ──────────────────────────────────────────────────────────────────
-- The in-world HUD was removed (to be redesigned), so the old 500ms push loop that
-- fed cash/bank/health/armor is gone. The `exports('hud', ...)` above is kept as a
-- no-op-friendly entry point for the future HUD; nothing auto-pushes right now.
