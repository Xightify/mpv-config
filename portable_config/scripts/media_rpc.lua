-- media_rpc v0.4
-- shows custom_name > metadata (youtube) > filename (filename without extensions)
-- https://github.com/Xightify/mpv-config
local mp = require("mp")
local msg = require("mp.msg")
local options = require("mp.options")
local utils = require("mp.utils")

local o = {
    client_id = "",
    enabled = false,
    refresh_interval = 2,
    osd_message_duration = 0.6,

    large_image_key = "mpv",
    large_image_text = "mpv",
    custom_name = "",

    audio_activity_type = 2,
    video_activity_type = 3,

    toggle_key = "Ctrl+F9",
    set_image_key = "Ctrl+F10",
    set_text_key = "Ctrl+F11",
    set_title_key = "Ctrl+F12",
    clear_image_key = "Ctrl+F6",
    clear_text_key = "Ctrl+F7",
    clear_title_key = "Ctrl+F8",
    clear_custom_name_key = "Ctrl+F5",

    button1_label = "",
    button1_url = "",
    button2_label = "",
    button2_url = "",
}

options.read_options(o, "media_rpc")

local defaults = {
    large_image_key = o.large_image_key,
    large_image_text = o.large_image_text,
    custom_name = o.custom_name,
}

local state = {
    timer = nil,
    rpc = nil,
    last_activity_json = nil,
    session_started_at = os.time(),
    display_name = nil,
    title_override = nil,
    custom_name_cleared = false,
}

local function trim(v)
    local s = (v or ""):gsub("^%s+", "")
    s = s:gsub("%s+$", "")
    return s
end

local function show_status(text)
    mp.osd_message(text, o.osd_message_duration)
end

local function split_path(path)
    if not path then return nil end
    local p = path:gsub("\\", "/")
    return p:match("([^/]+)$") or p
end

local function strip_extension(name)
    if not name then return nil end
    return name:gsub("%.[^%.]+$", "")
end

local function normalize_spaces(value)
    return trim((value or "")
        :gsub("[._]+", " ")
        :gsub("%s+", " "))
end

local function remove_balanced_segments(value)
    local s = value or ""
    s = s:gsub("%b[]", " ")
    s = s:gsub("%b{}", " ")
    s = s:gsub("%b()", " ")
    return s
end

local function file_name_without_extension()
    local path = mp.get_property("path")
    local source = split_path(path) or mp.get_property("media-title") or "Media"
    source = strip_extension(source)
    source = normalize_spaces(remove_balanced_segments(source))
    source = normalize_spaces(source)
    return source ~= "" and source or "Media"
end

local function metadata_display_name()
    local metadata = mp.get_property_native("metadata") or {}
    local candidates = {
        metadata.title,
        metadata.Title,
        metadata.TITLE,
        metadata["icy-title"],
    }

    for _, value in ipairs(candidates) do
        value = normalize_spaces(value)
        if value ~= "" then
            return value
        end
    end

    return nil
end

local function default_display_name()
    local custom_name = trim(o.custom_name)
    if custom_name ~= "" then
        return custom_name
    end

    return metadata_display_name() or file_name_without_extension()
end

local function refresh_display_name()
    if state.title_override then
        state.display_name = state.title_override
    else
        state.display_name = default_display_name()
    end
end

local function replace_tokens(value)
    local filename = state.display_name or default_display_name() or "Media"
    local path = mp.get_property("path") or ""

    return (value or "")
        :gsub("{filename}", filename)
        :gsub("{title}", filename)
        :gsub("{path}", path)
end

local function build_buttons()
    local buttons = {}

    local l1 = trim(replace_tokens(o.button1_label))
    local u1 = trim(replace_tokens(o.button1_url))
    if l1 ~= "" and u1 ~= "" then
        table.insert(buttons, { label = l1, url = u1 })
    end

    local l2 = trim(replace_tokens(o.button2_label))
    local u2 = trim(replace_tokens(o.button2_url))
    if l2 ~= "" and u2 ~= "" then
        table.insert(buttons, { label = l2, url = u2 })
    end

    return #buttons > 0 and buttons or nil
end

local function open_console_with_text(text, hint)
    show_status(hint)

    pcall(function()
        mp.commandv("script-binding", "console/enable")
    end)

    mp.add_timeout(0.05, function()
        pcall(function()
            mp.commandv("script-message-to", "console", "type", text)
        end)
    end)
end

local function detect_kind()
    local tracks = mp.get_property_native("track-list") or {}

    for _, track in ipairs(tracks) do
        if track.type == "video" and not track.albumart then
            return "video"
        end
    end

    return "audio"
end

local function to_le32(n)
    n = tonumber(n) or 0
    return string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    )
end

local function from_le32(v)
    local a,b,c,d = v:byte(1,4)
    return a + b*256 + c*65536 + d*16777216
end

local function rpc_close()
    if state.rpc then
        pcall(function() state.rpc:close() end)
        state.rpc = nil
    end
end

local function rpc_write(opcode, payload)
    if not state.rpc then return false end

    local packet = to_le32(opcode) .. to_le32(#payload) .. payload
    local ok = state.rpc:write(packet)

    if not ok then
        rpc_close()
        return false
    end

    state.rpc:flush()
    return true
end

local function rpc_read()
    if not state.rpc then return nil end

    local header = state.rpc:read(8)
    if not header or #header ~= 8 then
        rpc_close()
        return nil
    end

    local opcode = from_le32(header:sub(1,4))
    local length = from_le32(header:sub(5,8))

    local payload = state.rpc:read(length)
    if not payload or #payload ~= length then
        rpc_close()
        return nil
    end

    return opcode, utils.parse_json(payload)
end

local function rpc_connect()
    if state.rpc then return true end
    if o.client_id == "" then return false end

    for i = 0, 9 do
        local pipe = io.open(string.format("\\\\?\\pipe\\discord-ipc-%d", i), "r+b")

        if pipe then
            state.rpc = pipe

            local handshake = utils.format_json({
                v = 1,
                client_id = o.client_id
            })

            if not rpc_write(0, handshake) then
                break
            end

            local _, response = rpc_read()
            if response and response.evt == "READY" then
                return true
            end

            rpc_close()
        end
    end

    return false
end

local function build_activity()
    local title = state.display_name or default_display_name() or "Media"

    local time_pos = mp.get_property_number("time-pos")
    local duration = mp.get_property_number("duration")
    local paused = mp.get_property_native("pause")
    local now = os.time()

    local kind = detect_kind()

    local activity = {
        type = kind == "audio" and o.audio_activity_type or o.video_activity_type,
        name = title,
        details = title,
        state = paused and "Paused" or "Playing",

        assets = {
            large_image = o.large_image_key,
            large_text = o.large_image_text,
        },

        buttons = build_buttons(),
    }

    if time_pos and duration and not paused then
        activity.timestamps = {
            start = math.floor(now - time_pos),
            ["end"] = math.floor(now + math.max(duration - time_pos, 0))
        }
    elseif time_pos then
        activity.timestamps = {
            start = math.floor(state.session_started_at)
        }
    end

    return activity
end

local function publish_activity()
    if not o.enabled then return end

    local activity = build_activity()
    local json = utils.format_json(activity)

    if json == state.last_activity_json then return end
    if not rpc_connect() then return end

    local payload = utils.format_json({
        cmd = "SET_ACTIVITY",
        nonce = tostring(os.time()) .. tostring(math.random(1000,9999)),
        args = {
            pid = (utils.getpid and utils.getpid() or 0),
            activity = activity
        }
    })

    if rpc_write(1, payload) then
        state.last_activity_json = json
    end
end

local function stop_timer()
    if state.timer then
        state.timer:kill()
        state.timer = nil
    end
end

local function start_timer()
    stop_timer()
    state.timer = mp.add_periodic_timer(o.refresh_interval, publish_activity)
end

local function set_enabled(v)
    o.enabled = v == true
    state.last_activity_json = nil

    if not o.enabled then
        stop_timer()
        rpc_close()
        show_status("Media RPC: OFF")
        return
    end

    refresh_display_name()
    state.session_started_at = os.time() - (mp.get_property_number("time-pos") or 0)

    start_timer()
    publish_activity()
    show_status("Media RPC: ON")
end

mp.register_script_message("media-rpc-toggle", function()
    set_enabled(not o.enabled)
end)

mp.register_script_message("media-rpc-set-image", function(...)
    o.large_image_key = trim(table.concat({...}, " "))
    state.last_activity_json = nil
    publish_activity()
end)

mp.register_script_message("media-rpc-set-text", function(...)
    o.large_image_text = trim(table.concat({...}, " "))
    state.last_activity_json = nil
    publish_activity()
end)

mp.register_script_message("media-rpc-set-title", function(...)
    state.title_override = trim(table.concat({...}, " "))
    state.display_name = state.title_override
    state.last_activity_json = nil
    publish_activity()
end)

mp.register_script_message("media-rpc-clear-image", function()
    o.large_image_key = defaults.large_image_key
    state.last_activity_json = nil
    publish_activity()
    show_status("Media RPC: Image cleared")
end)

mp.register_script_message("media-rpc-clear-text", function()
    o.large_image_text = defaults.large_image_text
    state.last_activity_json = nil
    publish_activity()
    show_status("Media RPC: Text cleared")
end)

mp.register_script_message("media-rpc-clear-title", function()
    state.title_override = nil
    refresh_display_name()
    state.last_activity_json = nil
    publish_activity()
    show_status("Media RPC: Title cleared")
end)

mp.register_script_message("media-rpc-toggle-custom-name", function()
    if trim(o.custom_name) ~= "" then
        o.custom_name = ""
        state.custom_name_cleared = true
        show_status("Media RPC: Custom name OFF")
    else
        o.custom_name = defaults.custom_name
        state.custom_name_cleared = false
        show_status("Media RPC: Custom name ON")
    end

    refresh_display_name()
    state.last_activity_json = nil
    publish_activity()
end)

mp.register_event("file-loaded", function()
    refresh_display_name()
    state.session_started_at = os.time()
    state.last_activity_json = nil

    if o.enabled then
        start_timer()
        publish_activity()
    end
end)

mp.register_event("end-file", function()
    stop_timer()
    state.last_activity_json = nil
end)

mp.register_event("shutdown", function()
    stop_timer()
    rpc_close()
end)

mp.observe_property("pause", "bool", function()
    publish_activity()
end)

mp.observe_property("metadata", "native", function()
    if not o.enabled or state.title_override then
        return
    end

    local previous = state.display_name
    refresh_display_name()
    if state.display_name ~= previous then
        state.last_activity_json = nil
        publish_activity()
    end
end)

if o.toggle_key ~= "" then
    mp.add_forced_key_binding(o.toggle_key, "media-rpc-toggle-key", function()
        set_enabled(not o.enabled)
    end)
end

if o.set_image_key ~= "" then
    mp.add_forced_key_binding(o.set_image_key, "media-rpc-set-image-key", function()
        open_console_with_text(
            "script-message media-rpc-set-image ",
            "Media RPC: Set Image"
        )
    end)
end

if o.set_text_key ~= "" then
    mp.add_forced_key_binding(o.set_text_key, "media-rpc-set-text-key", function()
        open_console_with_text(
            "script-message media-rpc-set-text ",
            "Media RPC: Set Text"
        )
    end)
end

if o.set_title_key ~= "" then
    mp.add_forced_key_binding(o.set_title_key, "media-rpc-set-title-key", function()
        open_console_with_text(
            "script-message media-rpc-set-title ",
            "Media RPC: Set Title"
        )
    end)
end

if o.clear_image_key ~= "" then
    mp.add_forced_key_binding(o.clear_image_key, "media-rpc-clear-image-key", function()
        mp.commandv("script-message", "media-rpc-clear-image")
    end)
end

if o.clear_text_key ~= "" then
    mp.add_forced_key_binding(o.clear_text_key, "media-rpc-clear-text-key", function()
        mp.commandv("script-message", "media-rpc-clear-text")
    end)
end

if o.clear_title_key ~= "" then
    mp.add_forced_key_binding(o.clear_title_key, "media-rpc-clear-title-key", function()
        mp.commandv("script-message", "media-rpc-clear-title")
    end)
end

if o.clear_custom_name_key ~= "" then
    mp.add_forced_key_binding(o.clear_custom_name_key, "media-rpc-toggle-custom-name-key", function()
        mp.commandv("script-message", "media-rpc-toggle-custom-name")
    end)
end
