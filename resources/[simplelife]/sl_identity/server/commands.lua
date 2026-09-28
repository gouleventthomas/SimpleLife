--[[
    server/commands.lua — DEV replay commands for the whole new-spawn stack.

    Lets you iterate on the arrival cinematic / character UI WITHOUT reconnecting.
    Gated to the dev environment (GlobalState.slCoreEnv == 'dev', set by sl_core's
    boot). In prod these no-op. All are server commands that drive the SAME client
    events the real flow uses, so a replay exercises the exact production paths.

      /arrival     replay the FULL plane arrival cinematic (descent -> tarmac),
                   reusing your current character's model. The "try the whole
                   new-spawn stack" button.
      /charcreate  re-open the character CREATE screen (cancel enabled).
      /charselect  re-open the character SELECT screen (re-runs the real entry query).
      /resume      replay the no-plane RESUME fade-in at your character's coords.
]]

local function isDev()
    return GlobalState.slCoreEnv == 'dev'
end

-- Resolve the player source; reject console (source 0) and non-dev environments.
local function devPlayer(source)
    if source == 0 then
        print('^3[sl_identity]^7 this command must be run in-game by a player.')
        return nil
    end
    if not isDev() then
        print('^3[sl_identity]^7 dev commands are disabled (env != dev).')
        return nil
    end
    return source
end

-- /arrival [N] — replay the full arrival cinematic for yourself. With N>1 it SIMULATES a
-- batch of N (shared-start lead active) so you can exercise the 1b lockstep timing from a
-- single account: the plane sits at frame 1 for the lead, then flies. (Other passengers
-- don't appear solo — co-presence needs a 2nd real client.)
RegisterCommand('arrival', function(source, args)
    local src = devPlayer(source)
    if not src then return end
    local char = exports.sl_core:getChar(src)
    local model = (char and char.model) or Config.Models.m
    local n = math.floor(tonumber(args and args[1]) or 1)
    if n < 1 then n = 1 end
    Config.Log('info', ('/arrival replay src=%d (model=%s, simBatch=%d)'):format(src, tostring(model), n))
    Arrival.begin({ { src = src, model = model, appearance = char and char.appearance } }, { simBatch = n })
end, false)

-- /queuejoin — enqueue YOURSELF in the real arrival queue (test the batching/depart timing
-- solo: watch it depart as a batch of 1 after the window == the 1a path).
RegisterCommand('queuejoin', function(source)
    local src = devPlayer(source)
    if not src then return end
    if not (ArrivalQueue and ArrivalQueue.enqueue) then
        print('^1[sl_identity]^7 ArrivalQueue indisponible (queue.lua non chargé ?)')
        return
    end
    local char = exports.sl_core:getChar(src)
    local model = (char and char.model) or Config.Models.m
    ArrivalQueue.enqueue({ src = src, model = model, appearance = char and char.appearance })
end, false)

-- /queuestatus — print the live arrival queue (size, per-member age, ms before depart).
RegisterCommand('queuestatus', function(source)
    local src = devPlayer(source)
    if not src then return end
    if not (ArrivalQueue and ArrivalQueue.status) then
        print('^1[sl_identity]^7 ArrivalQueue indisponible (queue.lua non chargé ?)')
        return
    end
    local s = ArrivalQueue.status()
    print(('^4[sl_identity]^7 queue: %d en attente, ~%ds avant départ')
        :format(s.count, math.floor((s.remainingMs or 0) / 1000)))
    for _, line in ipairs(s.members) do print('   ' .. line) end
end, false)

-- /customize — re-open the fivem-appearance creator for your character (saves on finish).
RegisterCommand('customize', function(source)
    local src = devPlayer(source)
    if not src then return end
    local char = exports.sl_core:getChar(src)
    local model = (char and char.model) or Config.Models.m
    Config.Log('info', ('/customize src=%d (model=%s)'):format(src, tostring(model)))
    TriggerClientEvent('sl_identity:customize', src, { model = model })
end, false)

-- /deletechar — SOFT-DELETE all your characters (sets deleted_at) and restart from
-- scratch: the client fades to black and re-enters the create flow (0 char left).
RegisterCommand('deletechar', function(source)
    local src = devPlayer(source)
    if not src then return end
    local license = (IdentityServer and IdentityServer.getLicense) and IdentityServer.getLicense(src) or nil
    if not license then
        print('^3[sl_identity]^7 /deletechar: pas de license pour ce joueur.')
        return
    end
    local ok = pcall(function()
        exports.sl_core:dbUpdate(
            'UPDATE characters SET deleted_at = CURRENT_TIMESTAMP WHERE license = ? AND deleted_at IS NULL',
            { license })
    end)
    if not ok then
        print('^1[sl_identity]^7 /deletechar: échec de la suppression DB.')
        return
    end
    Config.Log('info', ('/deletechar src=%d license=%s — perso(s) supprimé(s) -> restart'):format(src, license))
    TriggerClientEvent('sl_identity:wipe', src)
end, false)

-- /charcreate — re-open the create screen (cancel enabled so you can back out).
RegisterCommand('charcreate', function(source)
    local src = devPlayer(source)
    if not src then return end
    Config.Log('info', ('/charcreate src=%d'):format(src))
    TriggerClientEvent('sl_identity:openCreate', src, { canCancel = true })
end, false)

-- /charselect — re-run the real entry decision (re-query chars -> open select/create).
RegisterCommand('charselect', function(source)
    local src = devPlayer(source)
    if not src then return end
    Config.Log('info', ('/charselect src=%d'):format(src))
    if IdentityServer and IdentityServer.openEntry then
        IdentityServer.openEntry(src)
    else
        print('^1[sl_identity]^7 openEntry not available (main.lua not loaded?)')
    end
end, false)

-- /resume — replay the no-plane resume fade-in at the loaded character's coords.
RegisterCommand('resume', function(source)
    local src = devPlayer(source)
    if not src then return end
    local char = exports.sl_core:getChar(src)
    if not char then
        print('^3[sl_identity]^7 /resume: no character loaded for this player.')
        return
    end
    Config.Log('info', ('/resume replay src=%d'):format(src))
    TriggerClientEvent('sl_identity:resume', src, {
        model  = char.model,
        coords = char.coords or {},
    })
end, false)

-- ── receive + save a recording (from /stoprecarrivage OR /stoprecbus) ─────────
-- The client can't write files freely, so it ships the sampled path here and we
-- persist it. `kind` routes it: 'bus' -> recordings/bus_last.json (the shuttle
-- route), anything else -> recordings/arrival_last.json (the plane flight). Both
-- are replayed by the client during the arrival.
RegisterNetEvent('sl_identity:saveRecording', function(samples, kind)
    if GlobalState.slCoreEnv ~= 'dev' then return end
    if type(samples) ~= 'table' then return end
    local file = (kind == 'bus') and 'recordings/bus_last.json' or 'recordings/arrival_last.json'
    local ok = pcall(function()
        SaveResourceFile(GetCurrentResourceName(), file, json.encode(samples), -1)
    end)
    if ok then
        Config.Log('info', ('saved recording: %d frames -> %s'):format(#samples, file))
    else
        Config.Log('error', 'failed to save recording: ' .. file)
    end
end)
