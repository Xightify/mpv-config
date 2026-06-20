-- Press Alt+F7 to cycle subtitle styles.
-- https://github.com/Xightify/mpv-config

local mp = require "mp"
local options = require "mp.options"

local o = {
    cycle_key = "Alt+F7",
    osd_message_duration = 0.5,
}

options.read_options(o, "subtitle")

-- Used for every normal subtitle preset. The YouTube preset overrides this.
local default_border_style = "outline-and-shadow"

-- This is the default preset in the cycle.
-- It mirrors the subtitle settings you normally keep in mpv.conf.
local default_style = {
    name = "Default",
    font = "Gandhi Sans",
    size = 50,
    spacing = 0.0,
    color = "#FFFFFFFF",
    border_color = "#FF000000",
    border_size = 2.4,
    blur = 0.1,
    shadow_color = "#70000000",
    shadow_offset = 0.9,
    bold = true,
    italic = false,
    pos = 100,
    margin_x = 19,
    margin_y = 34,
    align_x = "center",
    align_y = "bottom",
}

-- Add, remove, or reorder presets here.
local styles = {
    {
        name = "Netflix Sans",
        font = "Netflix Sans Bold",
        size = 50,
        spacing = 0,
        color = "#FFFFFFFF",
        border_color = "#FF000000",
        border_size = 2,
        blur = 0.15,
        shadow_color = "#A0000000",
        shadow_offset = 0.75,
        bold = false,
        italic = false,
        pos = 100,
    },
    {
        name = "Gabarito",
        font = "Gabarito Regular",
        size = 44,
        spacing = 0.0,
        color = "#FFFFFFFF",
        border_color = "#00000000",
        border_size = 0.0,
        border_style = "background-box",
        back_color = "#88000000",
        -- background-box draws a translucent rectangle behind the subtitle block.
        -- In this mode, back_color controls the box color.
        blur = 0.0,
        shadow_offset = 8.0,
        bold = false,
        italic = false,
        pos = 100,
    },
    -- {
    --     name = "Cinema",
    --     font = "Georgia",
    --     size = 50,
    --     spacing = 0.4,
    --     color = "#FFF8F1D8",
    --     border_color = "#FF111111",
    --     border_size = 3.5,
    --     blur = 0.6,
    --     shadow_color = default_style.shadow_color,
    --     shadow_offset = 2.0,
    --     bold = false,
    --     italic = true,
    -- },
    default_style,
}

local current_style = 0

local function set_bool_property(name, value)
    mp.set_property(name, value and "yes" or "no")
end

local function apply_style(style)
    -- These map directly to mpv subtitle options such as sub-font and sub-color.
    mp.set_property("sub-font", style.font)
    mp.set_property_number("sub-font-size", style.size)
    mp.set_property_number("sub-spacing", style.spacing)
    mp.set_property("sub-color", style.color)
    mp.set_property("sub-border-color", style.border_color)
    mp.set_property_number("sub-border-size", style.border_size)

    if style.border_style then
        mp.set_property("sub-border-style", style.border_style)
    else
        -- Reset the YouTube background box when switching back to a normal preset.
        mp.set_property("sub-border-style", default_border_style)
    end

    mp.set_property_number("sub-pos", style.pos or default_style.pos)
    mp.set_property_number("sub-margin-x", style.margin_x or default_style.margin_x)
    mp.set_property_number("sub-margin-y", style.margin_y or default_style.margin_y)
    mp.set_property("sub-align-x", style.align_x or default_style.align_x)
    mp.set_property("sub-align-y", style.align_y or default_style.align_y)

    if style.back_color then
        mp.set_property("sub-back-color", style.back_color)
    else
        mp.set_property("sub-shadow-color", style.shadow_color)
    end
    mp.set_property_number("sub-blur", style.blur)
    mp.set_property_number("sub-shadow-offset", style.shadow_offset)
    set_bool_property("sub-bold", style.bold)
    set_bool_property("sub-italic", style.italic)
end

local function cycle_subtitle_style()
    current_style = current_style + 1

    if current_style > #styles then
        current_style = 1
    end

    local style = styles[current_style]
    apply_style(style)
    mp.osd_message(("Subtitle style: %s (%d/%d)"):format(
        style.name,
        current_style,
        #styles
    ), o.osd_message_duration)
end

if o.cycle_key ~= "" then
    mp.add_key_binding(o.cycle_key, "cycle-subtitle-style", cycle_subtitle_style)
end

-- === Reference ===
-- 
--
-- Preset options:
--
-- name:
--   Label shown in mpv's on-screen message.
--
-- font:
--   Subtitle font family. Example: "Arial", "Gandhi Sans", "Century Gothic".
--
-- size:
--   Subtitle font size. Maps to mpv's sub-font-size.
--
-- spacing:
--   Horizontal letter spacing. Positive values spread letters out; negative values tighten them. Maps to sub-spacing.
--
-- color:
--   Text color. Uses mpv's #AARRGGBB color format.
--
-- border_color:
--   Outline color around subtitle text. Maps to sub-border-color.
--
-- border_size:
--   Outline thickness. Set to 0.0 for no outline. Maps to sub-border-size.
--
-- border_style:
--   Optional. Leave it out for normal subtitles.
--   "outline-and-shadow" = normal outline/shadow subtitles.
--   "opaque-box" = box behind each subtitle line.
--   "background-box" = one box behind the whole subtitle block, YouTube-style.
--
-- blur:
--   Softens the outline/box edge. Maps to sub-blur.
--
-- shadow_color:
--   Shadow color for normal subtitles. Maps to sub-shadow-color.
--
-- back_color:
--   Background/box color for boxed subtitle styles. For background-box, this becomes the box color. Maps to sub-back-color.
--
-- shadow_offset:
--   Shadow distance for normal subtitles. For background-box, this becomes padding around the text. Maps to sub-shadow-offset.
--
-- pos:
--   Optional. Vertical subtitle position percentage. Maps to sub-pos.
--   Falls back to default_style.pos when omitted.
--   Default = 100
--
-- margin_x:
--   Optional. Left and right subtitle screen margin in scaled pixels.
--   Maps to sub-margin-x. Falls back to default_style.margin_x when omitted.
--   Default = 19
--
-- margin_y:
--   Optional. Top and bottom subtitle screen margin in scaled pixels.
--   Maps to sub-margin-y. Falls back to default_style.margin_y when omitted.
--   Default = 34
--
-- align_x:
--   Optional. Horizontal subtitle alignment: "left", "center", or "right".
--   Maps to sub-align-x. Falls back to default_style.align_x when omitted.
--   Default = "center"
--
-- align_y:
--   Optional. Vertical subtitle alignment: "top", "center", or "bottom".
--   Maps to sub-align-y. Falls back to default_style.align_y when omitted.
--   Default = "bottom"
--
-- bold:
--   true or false. Maps to sub-bold.
--
-- italic:
--   true or false. Maps to sub-italic.
--
-- Color format:
--
-- mpv colors use #AARRGGBB.
-- AA = opacity, RR = red, GG = green, BB = blue.
-- Example: #88000000 is translucent black, #FFFFFFFF is solid white.
--
-- Useful translucent black values:
--
-- #B8000000 = darker
-- #88000000 = lighter
-- #66000000 = even lighter
-- #44000000 = very light
--
-- Notes:
--
-- Default positioning values match mpv's normal subtitle defaults:
-- pos = 100, margin_x = 19, margin_y = 34, align_x = "center", align_y = "bottom".
--
-- Normal styles (outline-and-shadow) use shadow_color with sub-shadow-color.
-- Boxed styles (opaque-box, background-box) can use back_color with sub-back-color, so the box color is separate from the normal subtitle shadow setting.
--
-- The commented Cinema preset uses default_style.shadow_color so it keeps the same shadow color as your main Default preset while changing only the parts that make it look cinematic.
