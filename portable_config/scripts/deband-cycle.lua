-- deband-cycle.lua
-- https://github.com/Xightify/mpv-config

-- Press Shift+F7 to cycle deband profiles.

local mp = require "mp"
local options = require "mp.options"

local o = {
    cycle_key = "Shift+F7",
    osd_message_duration = 0.5,
}

options.read_options(o, "deband-cycle")

-- This is the default profile in the cycle.
-- Add your normal mpv.conf deband values here.
local default_profile = {
    name = "Default",
    enabled = true,
    iterations = 2,
    threshold = 64,
    range = 17,
    grain = 12,
}

-- Add, remove, or reorder profiles here.
-- grain = 0 gives you a no-grain profile.
local profiles = {
    {
        name = "Light",
        enabled = true,
        iterations = 1,
        threshold = 24,
        range = 12,
        grain = 8,
    },
    {
        name = "Balanced",
        enabled = true,
        iterations = 2,
        threshold = 32,
        range = 16,
        grain = 16,
    },
    {
        name = "Strong",
        enabled = true,
        iterations = 3,
        threshold = 48,
        range = 20,
        grain = 24,
    },
    {
        name = "Extreme",
        enabled = true,
        iterations = 4,
        threshold = 64,
        range = 24,
        grain = 32,
    },
    {
        name = "Off",
        enabled = false,
        iterations = default_profile.iterations,
        threshold = default_profile.threshold,
        range = default_profile.range,
        grain = 0,
    },
    default_profile,
}

local current_profile = 0

local function set_bool_property(name, value)
    mp.set_property(name, value and "yes" or "no")
end

local function apply_profile(profile)
    set_bool_property("deband", profile.enabled)
    mp.set_property_number("deband-iterations", profile.iterations or default_profile.iterations)
    mp.set_property_number("deband-threshold", profile.threshold or default_profile.threshold)
    mp.set_property_number("deband-range", profile.range or default_profile.range)
    mp.set_property_number("deband-grain", profile.grain or default_profile.grain)
end

local function cycle_deband_profile()
    current_profile = current_profile + 1

    if current_profile > #profiles then
        current_profile = 1
    end

    local profile = profiles[current_profile]
    apply_profile(profile)
    mp.osd_message(("Deband profile: %s (%d/%d)"):format(
        profile.name,
        current_profile,
        #profiles
    ), o.osd_message_duration)
end

if o.cycle_key ~= "" then
    mp.add_key_binding(o.cycle_key, "cycle-deband-profile", cycle_deband_profile)
end

-- === Reference ===
--
-- Profile options:
--
-- name:
--   Label shown in mpv's on-screen message.
--
-- enabled:
--   true or false. Maps to mpv's deband option.
--
-- iterations:
--   Deband pass count. Maps to deband-iterations.
--
-- threshold:
--   Banding detection threshold. Maps to deband-threshold.
--
-- range:
--   Pixel search range. Maps to deband-range.
--
-- grain:
--   Added grain amount. Maps to deband-grain.
--   Set to 0 for a no-grain profile.
--
-- Notes:
--
-- The Default profile is included at the end of the cycle so you can keep
-- your preferred everyday deband values in one obvious place.
