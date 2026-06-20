-- Adds language-aware exact seek bindings. Right/Left seek by 5 seconds when the active audio track is English, otherwise by 2 seconds.
-- https://github.com/Xightify

local function english_audio()
    local lang = (mp.get_property("current-tracks/audio/lang", "") or ""):lower()
    return lang == "eng" or lang == "en" or lang == "english"
end

local function amount()
    return english_audio() and 5 or 2
end

local function seek_forward()
    mp.commandv("seek", amount(), "relative", "exact")
end

local function seek_backward()
    mp.commandv("seek", -amount(), "relative", "exact")
end

mp.add_forced_key_binding("RIGHT", "lang-seek-forward", seek_forward, {
    repeatable = true
})

mp.add_forced_key_binding("LEFT", "lang-seek-backward", seek_backward, {
    repeatable = true
})
