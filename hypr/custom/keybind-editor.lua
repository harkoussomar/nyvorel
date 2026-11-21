-- Keep the actions and flags in their source files. The editor stores only
-- a replacement shortcut and description for each original binding group.
local function encode(value)
    return (value:gsub(".", function(byte) return ("%02x"):format(byte:byte()) end))
end

local function decode(value)
    if #value % 2 ~= 0 or value:find("[^%x]") then return nil end
    return (value:gsub("%x%x", function(byte) return string.char(tonumber(byte, 16)) end))
end

local function normalize(chord)
    local parts = {}
    for part in chord:gmatch("[^+]+") do
        parts[#parts + 1] = part:lower():match("^%s*(.-)%s*$")
    end
    local key = table.remove(parts) or ""
    table.sort(parts)
    parts[#parts + 1] = key
    return table.concat(parts, "+")
end

return function(native, config_home)
    local scope = "global"
    local groups, overrides = {}, {}
    local input = io.open(config_home .. "/nyvorel/keybind-overrides.tsv", "r")
    if input then
        for line in input:lines() do
            local id, chord, label = line:match("^(%x+)\t(%x*)\t(%x*)$")
            if id then
                id, chord, label = decode(id), decode(chord), decode(label)
                if id and chord and label and #chord <= 96 and #label <= 512
                        and not chord:find("[^%w_:+ ]") and not label:find("%c") then
                    overrides[id] = {chord = chord, label = label}
                end
            end
        end
        input:close()
    end

    local proxy = setmetatable({}, {__index = native})

    local capture_map = "nyvorel-record-shortcut"
    local capture_generation = 0
    native.define_submap(capture_map, function()
        native.bind("Escape", native.dsp.submap("global"), {non_consuming = true, release = true})
    end)

    function _G.nyvorel_end_keybind_capture()
        if native.get_current_submap() == capture_map then
            native.dispatch(native.dsp.submap("global"))
        end
    end

    function _G.nyvorel_begin_keybind_capture()
        local current = native.get_current_submap()
        if current ~= "global" and current ~= "" then return end
        capture_generation = capture_generation + 1
        local generation = capture_generation
        native.dispatch(native.dsp.submap(capture_map))
        -- Restore normal shortcuts if the recorder's process is interrupted.
        native.timer(function()
            if generation == capture_generation then nyvorel_end_keybind_capture() end
        end, {timeout = 15000, type = "oneshot"})
    end

    function proxy.define_submap(name, callback, ...)
        return native.define_submap(name, function()
            local previous = scope
            scope = name
            callback()
            scope = previous
        end, ...)
    end

    function proxy.bind(chord, action, flags)
        if type(chord) ~= "string" then return native.bind(chord, action, flags) end
        local id = scope .. ":" .. normalize(chord)
        local group = groups[id]
        if not group then
            group = {scope = scope, default = chord, chord = chord, bindings = {}}
            groups[id] = group
        end
        local override = overrides[id]
        if override and override.chord ~= "" then group.chord = override.chord end
        local label = type(flags) == "table" and flags.description
        if type(label) == "string" and label ~= "" and not label:match("^%[hidden%]") then
            group.default_label = group.default_label or label
            if override and override.label ~= "" then
                local updated = {}
                for key, value in pairs(flags) do updated[key] = value end
                updated.description = override.label
                flags = updated
            end
            group.label = group.label or flags.description
        end

        local key = chord:lower():match("([^+%s]+)%s*$") or ""
        group.fixed = group.fixed or scope ~= "global" or key:match("^mouse")
            or key:match("^[a-z]+_[lr]$") or key == "catchall" or key:match("^switch:")
            or (type(flags) == "table" and (flags.mouse or flags.ignore_mods))
        local handle = native.bind(group.chord, action, flags)
        group.bindings[#group.bindings + 1] = {handle = handle, chord = chord, action = action, flags = flags}
        return handle
    end

    function proxy.unbind(chord, ...)
        if type(chord) ~= "string" then return native.unbind(chord, ...) end
        local id = scope .. ":" .. normalize(chord)
        local group = groups[id]
        groups[id] = nil
        return native.unbind(group and group.chord or chord, ...)
    end

    local function restore_overlaps()
        -- An optional tool or a personal configuration may claim a key after
        -- an edit has already been saved. Prefer existing bindings on reload.
        local restored
        repeat
            restored = false
            local slots = {}
            for _, group in pairs(groups) do
                local slot = group.scope .. ":" .. normalize(group.chord)
                slots[slot] = (slots[slot] or 0) + 1
            end
            for _, group in pairs(groups) do
                local slot = group.scope .. ":" .. normalize(group.chord)
                if slots[slot] > 1 and normalize(group.chord) ~= normalize(group.default) then
                    native.define_submap(group.scope, function()
                        for _, binding in ipairs(group.bindings) do
                            binding.handle:unbind()
                            binding.handle = native.bind(binding.chord, binding.action, binding.flags)
                        end
                    end)
                    group.chord = group.default
                    group.suspended = true
                    restored = true
                end
            end
        until not restored
    end

    local function publish()
        restore_overlaps()
        local runtime = os.getenv("XDG_RUNTIME_DIR")
        local instance = os.getenv("HYPRLAND_INSTANCE_SIGNATURE")
        if NYVOREL_VERIFY_ONLY or not runtime or not instance or not instance:match("^[%w_-]+$") then return end
        local path = runtime .. "/nyvorel-keybinds-" .. instance .. ".tsv"
        local temporary = path .. ".tmp"
        local output = io.open(temporary, "w")
        if not output then return end
        for id, group in pairs(groups) do
            if group.label then
                output:write(table.concat({
                    encode(id), encode(group.scope), encode(group.default), encode(group.chord),
                    encode(group.default_label), encode(group.label), tostring(#group.bindings),
                    group.fixed and "0" or "1", overrides[id] and "1" or "0", group.suspended and "1" or "0",
                }, "\t"), "\n")
            end
        end
        if output:close() then os.rename(temporary, path) end
    end

    return proxy, publish
end
