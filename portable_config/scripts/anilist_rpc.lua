-- anilist_rpc v0.5
-- https://github.com/Xightify/mpv-config
local mp = require("mp")
local msg = require("mp.msg")
local options = require("mp.options")
local utils = require("mp.utils")

local o = {
    client_id = "",
    enabled = false,
    refresh_interval = 2,
    curl_path = "curl",
    curl_timeout = 3,
    osd_message_duration = 0.6,
    error_osd_message_duration = 3,
    button_label = "View on AniList",
    button_link = "{anilist_url}",
    primary_button_enabled = true,
    custom_button_label = "",
    custom_button_url = "",
    activity_type = 3,
    title_language = "english",
    fallback_large_image_key = "",
    fallback_large_text = "",
    clear_on_no_match = false,
    toggle_key = "F9",
    toggle_movie_key = "Shift+F10",
    set_episode_key = "Shift+F11",
    clear_episode_key = "Shift+F12",
    set_id_key = "F10",
    set_title_key = "F11",
    clear_override_key = "F12",
}

options.read_options(o, "anilist_rpc")

-- Session-only state. Nothing here is written to disk.
local state = {
    timer = nil,
    lookup_request = nil,
    lookup_generation = 0,
    file_generation = 0,
    session_started_at = os.time(),
    current_path = nil,
    current_lookup_key = nil,
    current_guess = nil,
    current_match = nil,
    cache = {},
    override = nil,
    episode_override = nil,
    movie_display_override = nil,
    rpc = nil,
    warned_missing_client_id = false,
    last_activity_json = nil,
}

local ANILIST_SEARCH_QUERY = [[
query ($search: String) {
  Page(page: 1, perPage: 5) {
    media(search: $search, type: ANIME, sort: SEARCH_MATCH) {
      id
      siteUrl
      episodes
      format
      isAdult
      title {
        romaji
        english
        native
        userPreferred
      }
      synonyms
      coverImage {
        extraLarge
        large
      }
    }
  }
}
]]

local ANILIST_ID_QUERY = [[
query ($id: Int) {
  Media(id: $id, type: ANIME) {
    id
    siteUrl
    episodes
    format
    isAdult
    title {
      romaji
      english
      native
      userPreferred
    }
    synonyms
    coverImage {
      extraLarge
      large
    }
  }
}
]]

local function trim(value)
    local cleaned = (value or ""):gsub("^%s+", "")
    cleaned = cleaned:gsub("%s+$", "")
    return cleaned
end

local function show_status(text, seconds)
    mp.osd_message(text, seconds or o.osd_message_duration)
end

local function replace_tokens(value, match)
    local anime_name = match and (match.display_title or match.raw_title) or "Anime"
    local episode = match and match.episode or ""
    local anilist_url = match and match.site_url or ""
    return (value or "")
        :gsub("{title}", anime_name)
        :gsub("{episode}", tostring(episode))
        :gsub("{anilist_url}", anilist_url)
end

local function build_buttons(match)
    local buttons = {}

    local default_label = trim(replace_tokens(o.button_label, match))
    local default_url = trim(replace_tokens(o.button_link, match))
    if default_url == "" and match and match.site_url then
        default_url = match.site_url
    end

    if o.primary_button_enabled and default_label ~= "" and default_url ~= "" then
        table.insert(buttons, {
            label = default_label,
            url = default_url,
        })
    end

    local custom_label = trim(replace_tokens(o.custom_button_label, match))
    local custom_url = trim(replace_tokens(o.custom_button_url, match))
    if custom_label ~= "" and custom_url ~= "" then
        table.insert(buttons, {
            label = custom_label,
            url = custom_url,
        })
    end

    return #buttons > 0 and buttons or nil
end

local function open_console_with_text(text, hint, cursor_pos)
    show_status(hint)
    pcall(function()
        mp.commandv("script-binding", "console/enable")
    end)
    mp.add_timeout(0.05, function()
        pcall(function()
            if cursor_pos then
                mp.commandv("script-message-to", "console", "type", text, cursor_pos)
            else
                mp.commandv("script-message-to", "console", "type", text)
            end
        end)
    end)
end

local function is_enabled()
    return o.enabled == true
end

local function split_path(path)
    if not path then
        return nil
    end
    local normalized = path:gsub("\\", "/")
    return normalized:match("([^/]+)$") or normalized
end

local function strip_extension(name)
    if not name then
        return nil
    end
    return name:gsub("%.[^%.]+$", "")
end

local function normalize_spaces(value)
    return trim((value or ""):gsub("[._]+", " "):gsub("%s+", " "))
end

local function remove_balanced_segments(value)
    local cleaned = value or ""
    cleaned = cleaned:gsub("%b[]", " ")
    cleaned = cleaned:gsub("%b{}", " ")
    cleaned = cleaned:gsub("%b()", " ")
    return cleaned
end

local function normalize_compare(value)
    local normalized = (value or ""):lower()
    normalized = normalized:gsub("&", " and ")
    normalized = normalized:gsub("[^%w]+", "")
    return normalized
end

local function safe_number(value)
    local number = tonumber(value)
    if not number then
        return nil
    end
    return math.floor(number)
end

-- Remove common encode/release noise before AniList search.
local function clean_title_tokens(value)
    local cleaned = " " .. remove_balanced_segments(value or "") .. " "
    local patterns = {
        "%f[%a]%d%d?bit%f[%A]",
        "%f[%a]%d%d%d%dp%f[%A]",
        "%f[%a]x26[45]%f[%A]",
        "%f[%a]h%.?26[45]%f[%A]",
        "%f[%a]hevc%f[%A]",
        "%f[%a]av1%f[%A]",
        "%f[%a]aac%d?%f[%A]",
        "%f[%a]flac%f[%A]",
        "%f[%a]opus%f[%A]",
        "%f[%a]web[%s%-]?dl%f[%A]",
        "%f[%a]webrip%f[%A]",
        "%f[%a]bluray%f[%A]",
        "%f[%a]bdrip%f[%A]",
        "%f[%a]bd%f[%A]",
        "%f[%a]cr%f[%A]",
        "%f[%a]nf%f[%A]",
        "%f[%a]amzn%f[%A]",
        "%f[%a]dual[%s%-]?audio%f[%A]",
        "%f[%a]multi[%s%-]?sub%f[%A]",
        "%f[%a]subbed%f[%A]",
        "%f[%a]dubbed%f[%A]",
        "%f[%a]uncensored%f[%A]",
        "%f[%a]remux%f[%A]",
    }

    for _, pattern in ipairs(patterns) do
        cleaned = cleaned:gsub(pattern, " ")
    end

    cleaned = cleaned:gsub("^%s*%d%d?%d?%s+", " ")
    cleaned = cleaned:gsub("%s+[Ss]eason%s+%d+$", " ")
    cleaned = cleaned:gsub("%s+[Pp]art%s+%d+$", " ")
    cleaned = cleaned:gsub("%s+[Mm]ovie%s*$", " Movie ")
    cleaned = cleaned:gsub("%s+", " ")
    return trim(cleaned)
end

-- Detect common patterns:
-- S02E05, E03, Episode 03, Title - 03, 03 Title E03, [SubsPlease] ... [hash]
local function parse_episode_and_title(raw_name)
    local raw = normalize_spaces(remove_balanced_segments(raw_name or ""))
    local patterns = {
        { pattern = "^%d%d?%d?%s+(.-)%s+[Ee][Pp]?[%s%._%-]*(%d%d?%d?).*$" },
        { pattern = "^(.-)%s+[Ss](%d+)[%s%._%-]*[Ee](%d+).*$", season = true },
        { pattern = "^(.-)%s+[Ee](%d%d?%d?)%s*$" },
        { pattern = "^(.-)%s*[-_ ]+[Ee][Pp]?[%s%._%-]*(%d%d?%d?).*$" },
        { pattern = "^(.-)%s*[-_ ]+(%d%d?%d?)[Vv]?%d?%s*$" },
        { pattern = "^(.-)%s+[Ee]pisode[%s%._%-]*(%d%d?%d?).*$" },
    }

    for _, item in ipairs(patterns) do
        local title, first, second = raw:match(item.pattern)
        if title and first then
            local episode = item.season and second or first
            local season = item.season and first or nil
            return clean_title_tokens(title), safe_number(episode), safe_number(season)
        end
    end

    return clean_title_tokens(raw), nil, nil
end

local function extract_media_guess()
    local source = split_path(mp.get_property("path")) or mp.get_property("media-title")
    if not source then
        return nil
    end

    source = normalize_spaces(remove_balanced_segments(strip_extension(source)))
    local title, episode, season = parse_episode_and_title(source)
    title = normalize_spaces(title)
    if title == "" or #title < 2 then
        return nil
    end

    return {
        title = title,
        episode = episode,
        season = season,
        lookup_key = string.format("%s|s%s", normalize_compare(title), tostring(season or "")),
    }
end

local function title_variants(media)
    local titles = {}
    local seen = {}

    local function add(value)
        value = trim(value)
        if value == "" then
            return
        end
        local key = normalize_compare(value)
        if key == "" or seen[key] then
            return
        end
        seen[key] = true
        table.insert(titles, value)
    end

    if media.title then
        add(media.title.userPreferred)
        add(media.title.english)
        add(media.title.romaji)
        add(media.title.native)
    end

    if media.synonyms then
        for _, synonym in ipairs(media.synonyms) do
            add(synonym)
        end
    end

    return titles
end

local function score_candidate(query, episode, media)
    if media.isAdult then
        return -math.huge
    end

    local query_key = normalize_compare(query)
    local score = 0

    for _, title in ipairs(title_variants(media)) do
        local candidate_key = normalize_compare(title)
        if candidate_key == query_key then
            score = math.max(score, 120)
        elseif candidate_key:find(query_key, 1, true) then
            score = math.max(score, 100)
        elseif query_key:find(candidate_key, 1, true) then
            score = math.max(score, 92)
        elseif candidate_key:gsub("season%d+$", "") == query_key:gsub("season%d+$", "") then
            score = math.max(score, 88)
        end
    end

    if media.episodes and episode and episode <= media.episodes then
        score = score + 5
    end

    if media.format == "MOVIE" then
        score = score - 8
    end

    return score
end

local function build_fallback_match(title, episode, season)
    return {
        confirmed = false,
        display_title = title,
        raw_title = title,
        episode = episode,
        season = season,
    }
end

local function get_display_title(title, fallback_title)
    if not title then
        return fallback_title or "Anime"
    end

    local language = (o.title_language or "english"):lower()
    if language == "romaji" then
        return title.romaji or title.english or title.userPreferred or title.native or fallback_title or "Anime"
    elseif language == "english" then
        return title.english or title.romaji or title.userPreferred or title.native or fallback_title or "Anime"
    end

    msg.warn("Unknown title_language '" .. tostring(o.title_language) .. "', using english")
    return title.english or title.romaji or title.userPreferred or title.native or fallback_title or "Anime"
end

local function build_match_from_media(media, fallback_title, episode, season)
    if not media then
        return nil
    end

    return {
        confirmed = true,
        id = media.id,
        site_url = media.siteUrl,
        poster_url = (media.coverImage and (media.coverImage.extraLarge or media.coverImage.large)) or nil,
        display_title = get_display_title(media.title, fallback_title),
        media_format = media.format,
        episode = episode,
        season = season,
        raw_title = fallback_title or "Anime",
    }
end

local function stop_lookup_request()
    if state.lookup_request then
        state.lookup_generation = state.lookup_generation + 1
        pcall(function()
            mp.abort_async_command(state.lookup_request)
        end)
        state.lookup_request = nil
    end
end

local function stop_timer()
    if state.timer then
        state.timer:kill()
        state.timer = nil
    end
end

local function to_le32(number)
    local n = tonumber(number) or 0
    return string.char(
        n % 256,
        math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256,
        math.floor(n / 16777216) % 256
    )
end

local function from_le32(value)
    local a, b, c, d = value:byte(1, 4)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function rpc_close()
    if state.rpc then
        pcall(function()
            state.rpc:close()
        end)
        state.rpc = nil
    end
end

local function rpc_write(opcode, payload)
    if not state.rpc then
        return false
    end

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
    if not state.rpc then
        return nil
    end

    local header = state.rpc:read(8)
    if not header or #header ~= 8 then
        rpc_close()
        return nil
    end

    local opcode = from_le32(header:sub(1, 4))
    local length = from_le32(header:sub(5, 8))
    local payload = state.rpc:read(length)
    if not payload or #payload ~= length then
        rpc_close()
        return nil
    end

    return opcode, utils.parse_json(payload)
end

local function rpc_connect()
    if state.rpc then
        return true
    end

    if o.client_id == "" then
        if not state.warned_missing_client_id then
            msg.warn("Set client_id in script-opts/anilist_rpc.conf")
            state.warned_missing_client_id = true
        end
        return false
    end

    for index = 0, 9 do
        local handle = io.open(string.format("\\\\?\\pipe\\discord-ipc-%d", index), "r+b")
        if handle then
            state.rpc = handle
            local handshake = utils.format_json({ v = 1, client_id = o.client_id })
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

local function describe_state(match)
    local prefix = mp.get_property_native("pause") and "Paused" or "Watching"
    local show_movie = state.movie_display_override
    if show_movie == nil then
        show_movie = match and match.media_format == "MOVIE"
    end

    if show_movie then
        return prefix .. " Movie"
    end

    local episode = state.episode_override or (match and match.episode)
    if episode then
        return prefix .. " " .. string.format("Episode %02d", episode)
    end

    return prefix .. " Anime"
end

local function build_activity()
    if not is_enabled() then
        return nil
    end

    local match = state.current_match
    if not match then
        return nil
    end

    local anime_name = match.display_title or match.raw_title or "Anime"
    local time_pos = mp.get_property_number("time-pos")
    local duration = mp.get_property_number("duration")
    local paused = mp.get_property_native("pause")
    local now = os.time()

    local activity = {
        type = o.activity_type,
        name = anime_name,
        details = anime_name,
        state = describe_state(match),
        assets = {
            large_text = anime_name,
        },
    }

    -- Playing uses Spotify-like moving timestamps.
    -- Paused uses a fixed elapsed timer.
    if time_pos and duration and not paused then
        activity.timestamps = {
            start = math.floor(now - time_pos),
            ["end"] = math.floor(now + math.max(duration - time_pos, 0)),
        }
    elseif time_pos then
        activity.timestamps = {
            start = math.floor(state.session_started_at),
        }
    end

    if match.poster_url then
        activity.assets.large_image = match.poster_url
    elseif trim(o.fallback_large_image_key) ~= "" then
        activity.assets.large_image = trim(o.fallback_large_image_key)
        activity.assets.large_text = o.fallback_large_text
    else
        activity.assets.large_text = o.fallback_large_text
    end

    -- No image links. Buttons are configurable and may include AniList + one custom link.
    activity.buttons = build_buttons(match)

    return activity
end

local function publish_activity()
    if not is_enabled() then
        return
    end

    local activity = build_activity()
    if not activity then
        return
    end

    local activity_json = utils.format_json(activity)
    if activity_json == state.last_activity_json then
        return
    end

    if not rpc_connect() then
        return
    end

    local payload = utils.format_json({
        cmd = "SET_ACTIVITY",
        nonce = tostring(os.time()) .. tostring(math.random(1000, 9999)),
        args = {
            pid = (utils.getpid and utils.getpid() or 0),
            activity = activity,
        },
    })

    if rpc_write(1, payload) then
        state.last_activity_json = activity_json
    end
end

-- AniList is queried once per new file/load or manual override.
-- Late results from older files are ignored.
local function start_lookup(guess)
    if not is_enabled() then
        return
    end

    stop_lookup_request()
    state.lookup_generation = state.lookup_generation + 1
    local lookup_generation = state.lookup_generation
    local file_generation = state.file_generation
    local lookup_key = guess.lookup_key

    local query = ANILIST_SEARCH_QUERY
    local variables = { search = guess.title }
    if state.override and state.override.kind == "id" then
        query = ANILIST_ID_QUERY
        variables = { id = tonumber(state.override.value) }
    end

    local payload = {
        query = query,
        variables = variables,
    }

    state.lookup_request = mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true,
        args = {
            o.curl_path,
            "-sS",
            "-L",
            "--max-time",
            tostring(o.curl_timeout),
            "-H",
            "Content-Type: application/json",
            "-d",
            utils.format_json(payload),
            "https://graphql.anilist.co",
        },
    }, function(success, result, err)
        state.lookup_request = nil

        if lookup_generation ~= state.lookup_generation then
            return
        end

        if file_generation ~= state.file_generation then
            return
        end

        if err == "killed" or err == "canceled" then
            return
        end

        local match = nil
        if success and result and result.status == 0 then
            local decoded = utils.parse_json(result.stdout or "")
            if state.override and state.override.kind == "id" then
                local media = decoded and decoded.data and decoded.data.Media or nil
                match = build_match_from_media(media, guess.title, guess.episode, guess.season)
            else
                local media_list = decoded and decoded.data and decoded.data.Page and decoded.data.Page.media or {}
                local best_media = nil
                local best_score = 0
                for _, media in ipairs(media_list or {}) do
                    local score = score_candidate(guess.title, guess.episode, media)
                    if score > best_score then
                        best_score = score
                        best_media = media
                    end
                end
                if best_media and best_score >= 80 then
                    match = build_match_from_media(best_media, guess.title, guess.episode, guess.season)
                end
            end
        else
            msg.warn("AniList request failed: " .. tostring(err or (result and (result.error_string or result.stderr)) or "unknown error"))
        end

        if not match and not o.clear_on_no_match then
            match = build_fallback_match(guess.title, guess.episode, guess.season)
        end

        state.cache[lookup_key] = match or false
        if state.current_lookup_key == lookup_key and state.file_generation == file_generation then
            state.current_match = match
            publish_activity()
        end
    end)
end

local function refresh_current_media(force_lookup)
    if not is_enabled() then
        return
    end

    local guess = extract_media_guess()
    if not guess then
        state.current_path = nil
        state.current_lookup_key = nil
        state.current_guess = nil
        state.current_match = nil
        state.last_activity_json = nil
        return
    end

    if state.override and state.override.kind == "title" then
        guess.title = state.override.value
        guess.lookup_key = "override-title-" .. normalize_compare(state.override.value)
    elseif state.override and state.override.kind == "id" then
        guess.lookup_key = "override-id-" .. tostring(state.override.value)
    end

    local path = mp.get_property("path")
    state.session_started_at = os.time() - (mp.get_property_number("time-pos") or 0)

    if not force_lookup and path == state.current_path and guess.lookup_key == state.current_lookup_key then
        if state.current_match then
            state.current_match.episode = guess.episode
            state.current_match.season = guess.season
        end
        return
    end

    state.current_path = path
    state.current_lookup_key = guess.lookup_key
    state.current_guess = guess
    state.current_match = build_fallback_match(guess.title, guess.episode, guess.season)
    state.last_activity_json = nil

    if not force_lookup and state.cache[guess.lookup_key] ~= nil then
        local cached = state.cache[guess.lookup_key]
        state.current_match = cached or nil
        if state.current_match == false then
            state.current_match = nil
        end
        if state.current_match then
            state.current_match.episode = guess.episode
            state.current_match.season = guess.season
        end
        publish_activity()
        return
    end

    start_lookup(guess)
end

local function start_timer()
    if not is_enabled() then
        stop_timer()
        return
    end

    stop_timer()
    state.timer = mp.add_periodic_timer(o.refresh_interval, publish_activity)
end

local function reset_runtime()
    -- Keep unload/shutdown as cheap as possible.
    state.lookup_generation = state.lookup_generation + 1
    state.file_generation = state.file_generation + 1
    stop_timer()
    state.lookup_request = nil
    state.last_activity_json = nil
    state.current_path = nil
    state.current_lookup_key = nil
    state.current_guess = nil
    state.current_match = nil
    rpc_close()
end

local function set_enabled(enabled)
    o.enabled = enabled == true
    state.last_activity_json = nil

    if not o.enabled then
        stop_timer()
        stop_lookup_request()
        rpc_close()
        show_status("AniList RPC: OFF")
        return
    end

    show_status("AniList RPC: ON")
    start_timer()
    refresh_current_media(true)
end

mp.register_event("file-loaded", function()
    state.file_generation = state.file_generation + 1
    state.last_activity_json = nil
    state.current_path = nil
    state.current_lookup_key = nil
    state.current_guess = nil
    state.current_match = nil
    state.session_started_at = os.time()
    if is_enabled() then
        start_timer()
        refresh_current_media(false)
    end
end)

mp.register_event("end-file", function()
    stop_timer()
    state.lookup_generation = state.lookup_generation + 1
    state.lookup_request = nil
end)

mp.register_event("shutdown", function()
    reset_runtime()
end)

mp.observe_property("pause", "bool", function()
    if mp.get_property_native("pause") then
        state.session_started_at = os.time() - (mp.get_property_number("time-pos") or 0)
    end
    publish_activity()
end)

mp.observe_property("time-pos", "number", function()
    if not mp.get_property_native("pause") then
        state.session_started_at = os.time() - (mp.get_property_number("time-pos") or 0)
    end
end)

mp.register_script_message("anilist-rpc-set-id", function(...)
    local parts = { ... }
    local id_text = trim(table.concat(parts, " "))
    local numeric_id = tonumber(id_text)
    if not numeric_id then
        msg.error("Usage: script-message anilist-rpc-set-id <anilist_id>")
        show_status("AniList RPC: Set ID needs a number", o.error_osd_message_duration)
        return
    end

    state.override = {
        kind = "id",
        value = math.floor(numeric_id),
    }
    show_status("AniList RPC: Set ID " .. tostring(state.override.value))
    local ok, err = pcall(function()
        refresh_current_media(true)
    end)
    if not ok then
        msg.error("AniList set-id failed: " .. tostring(err))
        show_status("AniList RPC: Set ID failed", o.error_osd_message_duration)
    end
end)

mp.register_script_message("anilist-rpc-set-title", function(...)
    local parts = { ... }
    local title = trim(table.concat(parts, " "))
    if title == "" then
        msg.error('Usage: script-message anilist-rpc-set-title "anime title"')
        show_status("AniList RPC: Set Title is empty", o.error_osd_message_duration)
        return
    end

    state.override = {
        kind = "title",
        value = title,
    }
    show_status("AniList RPC: Set Title " .. title)
    local ok, err = pcall(function()
        refresh_current_media(true)
    end)
    if not ok then
        msg.error("AniList set-title failed: " .. tostring(err))
        show_status("AniList RPC: Set Title failed", o.error_osd_message_duration)
    end
end)

mp.register_script_message("anilist-rpc-clear-override", function()
    state.override = nil
    show_status("AniList RPC: Override cleared")
    local ok, err = pcall(function()
        refresh_current_media(true)
    end)
    if not ok then
        msg.error("AniList clear override failed: " .. tostring(err))
        show_status("AniList RPC: Override clear failed", o.error_osd_message_duration)
    end
end)

mp.register_script_message("anilist-rpc-toggle", function()
    set_enabled(not is_enabled())
end)

mp.register_script_message("anilist-rpc-set-episode", function(...)
    local parts = { ... }
    local episode_text = trim(table.concat(parts, " "))
    local numeric_episode = tonumber(episode_text)
    if not numeric_episode then
        msg.error("Usage: script-message anilist-rpc-set-episode <episode_number>")
        show_status("AniList RPC: Set Episode needs a number", o.error_osd_message_duration)
        return
    end

    state.episode_override = math.floor(numeric_episode)
    state.movie_display_override = false
    state.last_activity_json = nil
    publish_activity()
end)

mp.register_script_message("anilist-rpc-clear-episode", function()
    state.episode_override = nil
    state.last_activity_json = nil
    show_status("AniList RPC: Episode override cleared")
    publish_activity()
end)

mp.register_script_message("anilist-rpc-toggle-movie", function()
    local show_movie = state.movie_display_override
    if show_movie == nil then
        show_movie = state.current_match and state.current_match.media_format == "MOVIE"
    end

    state.movie_display_override = not show_movie
    local movie_status = "AniList RPC: Movie " .. (state.movie_display_override and "ON" or "OFF")
    show_status(movie_status)
    state.last_activity_json = nil
    publish_activity()
end)

if o.set_id_key ~= "" then
    mp.add_forced_key_binding(o.set_id_key, "anilist-rpc-set-id-key", function()
        open_console_with_text(
            "script-message anilist-rpc-set-id ",
            "AniList RPC: Set ID"
        )
    end)
end

if o.set_title_key ~= "" then
    mp.add_forced_key_binding(o.set_title_key, "anilist-rpc-set-title-key", function()
        open_console_with_text(
            "script-message anilist-rpc-set-title \"\"",
            "AniList RPC: Set Title",
            39
        )
    end)
end

if o.toggle_key ~= "" then
    mp.add_forced_key_binding(o.toggle_key, "anilist-rpc-toggle-key", function()
        set_enabled(not is_enabled())
    end)
end

if o.toggle_movie_key ~= "" then
    mp.add_forced_key_binding(o.toggle_movie_key, "anilist-rpc-toggle-movie-key", function()
        mp.commandv("script-message", "anilist-rpc-toggle-movie")
    end)
end

if o.set_episode_key ~= "" then
    mp.add_forced_key_binding(o.set_episode_key, "anilist-rpc-set-episode-key", function()
        open_console_with_text(
            "script-message anilist-rpc-set-episode ",
            "AniList RPC: Set Episode"
        )
    end)
end

if o.clear_episode_key ~= "" then
    mp.add_forced_key_binding(o.clear_episode_key, "anilist-rpc-clear-episode-key", function()
        mp.commandv("script-message", "anilist-rpc-clear-episode")
    end)
end

if o.clear_override_key ~= "" then
    mp.add_forced_key_binding(o.clear_override_key, "anilist-rpc-clear-override-key", function()
        state.override = nil
        show_status("AniList RPC: Override cleared")
        local ok, err = pcall(function()
            refresh_current_media(true)
        end)
        if not ok then
            msg.error("AniList clear override key failed: " .. tostring(err))
            show_status("AniList RPC: Override clear failed", o.error_osd_message_duration)
        end
    end)
end
