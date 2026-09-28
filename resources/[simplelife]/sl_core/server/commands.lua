--[[
    server/commands.lua — the /sl admin command.

    Subcommands:
      /sl info            — env, ready state, module + service count
      /sl modules         — list registered modules
      /sl db ping         — SELECT 1 round-trip
      /sl db status       — migration latch + counts
      /sl db migrations   — per-file migration status
      /sl save            — save all loaded characters (destructive-ish: ACE gated)

    ACE-gated under 'group.admin' for the whole command (registered with the ace
    string so non-admins don't even see suggestions). Each handler runs inside the
    command thread, which is a valid context for MySQL .await calls.
]]

local ACE = 'group.admin'

local function reply(src, msg)
    if src == 0 then
        Config.Log('info', msg)
    else
        TriggerClientEvent('chat:addMessage', src, {
            color = { 100, 200, 255 },
            multiline = true,
            args = { 'sl_core', msg },
        })
    end
end

lib.addCommand('sl', {
    help = 'SimpleLife core admin command',
    params = {
        { name = 'sub', help = 'info | modules | db | save', optional = true },
        { name = 'arg', help = 'ping | status | migrations', optional = true },
    },
    restricted = ACE,
}, function(source, args)
    local src = source
    local sub = (args.sub or 'info'):lower()
    local arg = (args.arg or ''):lower()

    if sub == 'info' then
        local services = SLCore.use('registry')
        local count = 0
        for _ in pairs(SLCore.modules) do count = count + 1 end
        reply(src, ('env=%s ready=%s modules=%d services=%d')
            :format(Config.Env, tostring(SLCore.ready), count, services and #services.list() or 0))

    elseif sub == 'modules' then
        local names = {}
        for k in pairs(SLCore.modules) do names[#names + 1] = k end
        table.sort(names)
        reply(src, ('modules: %s'):format(table.concat(names, ', ')))

    elseif sub == 'db' then
        local db = SLCore.use('db')
        if arg == 'ping' then
            reply(src, db and db.ping() and 'db ping: OK (SELECT 1)' or 'db ping: FAILED')
        elseif arg == 'status' then
            local st = SLCore.use('migrate').Status()
            reply(src, ('migrate: latched=%s applied=%d present=%d')
                :format(tostring(st.latched), st.applied, st.present))
        elseif arg == 'migrations' then
            local st = SLCore.use('migrate').Status()
            if #st.files == 0 then
                reply(src, 'no migration status yet (boot not complete?)')
            else
                for _, f in ipairs(st.files) do
                    reply(src, (' - %s [%s] provides=%s'):format(f.name, f.status, f.provides))
                end
            end
        else
            reply(src, 'usage: /sl db <ping|status|migrations>')
        end

    elseif sub == 'save' then
        local p = SLCore.use('players')
        local n = p and p.saveAll() or 0
        reply(src, ('saved %d character(s)'):format(n))

    else
        reply(src, 'usage: /sl <info|modules|db|save>')
    end
end)
