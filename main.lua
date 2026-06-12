-- Add throttle
local last_preview_time = 0
local preview_interval = 0.05 -- 50ms
-- Add spam-guard
local preview_visible = false

local mp = require("mp")
local options = require("mp.options")
local helper = require("helper")


-- Script options (configurable via mpv/script-opts/mpv_seekpeek.conf)
local opts = {
    auto_start = true,             -- Auto-start sprite generation on playback
    delete_sprite_on_exit = false, -- Delete sprite file when player quits
    auto_fullscreen = true,        -- Automatically set fullscreen on playback start
    preview_enabled = true,        -- Enable/disable preview overlay
    message_duration = 3,          -- Duration for OSD messages in seconds
    thumbnail_interval = 5,        -- Seconds between thumbnail samples
    preview_width = 240,           -- Preview thumbnail width in pixels
    preview_height = 100,          -- Preview thumbnail height in pixels
    sprite_grid_rows = 30,         -- Sprite sheet grid rows
    sprite_grid_cols = 30,         -- Sprite sheet grid columns
    key_generate = "T",            -- Key to manually trigger sprite generation
    key_regenerate = "Ctrl+T",     -- Key to force regenerate sprite (deletes existing)
    key_toggle_preview = "Ctrl+S", -- Key to toggle preview on/off
    key_delete_sprite = "Alt+T",   -- Key to delete cached sprite for current file
}

options.read_options(opts, "mpv_seekpeek")

Video_width = 0
Video_height = 0
Seekbar_x_start = 0
Seekbar_x_end = 0
Seekbar_y_start = 0
Seekbar_y_end = 0
Duration = 0
Last_overlay_id = 1 -- More reliable
Cache_dir = nil
Sprite_sheet_name = ""
Temp_prev_name = ""
Sprite_grid_rows = opts.sprite_grid_rows
Sprite_grid_cols = opts.sprite_grid_cols
Preview_img_w = opts.preview_width
Preview_img_h = opts.preview_height
Thumbnail_interval_in_sec = opts.thumbnail_interval
Sprite_generated = false
Platform = nil
Main_sprite = nil

local Generating_sprite = false

local function generate_sprite(force)
    if Generating_sprite then
        helper.showMessage("Sprite generation already in progress", opts.message_duration, true)
        return
    end
    local filepath = mp.get_property("path")
    if not filepath then
        helper.showMessage("No file loaded", opts.message_duration, true)
        return
    end

    -- Force regeneration: clean up existing sprite
    if force then
        if Main_sprite then Main_sprite:close() end
        Main_sprite = nil
        Sprite_generated = false
        if Sprite_sheet_name ~= "" then os.remove(Sprite_sheet_name) end
        mp.commandv("overlay_remove", Last_overlay_id)
    end

    -- Check if sprite already exists
    Main_sprite = io.open(Sprite_sheet_name, "rb")
    if Main_sprite then
        local size = Main_sprite:seek("end")

        if size and size > 0 then
            Main_sprite:seek("set", 0)
            Sprite_generated = true
            helper.showMessage("Pre-generated sprite found, ready for preview", opts.message_duration, true)
            return
        else
            Main_sprite:close()
            Main_sprite = nil
            Sprite_generated = false
            os.remove(Sprite_sheet_name)
        end
    end

    if not helper.isFFmpegAvailable() then
        local error_message = "Unable to find ffmpeg. Please install/add it to your PATH to use the script."
        helper.showMessage(error_message, opts.message_duration, true)
        return
    end

    Generating_sprite = true
    helper.showMessage("Generating sprite sheet...", opts.message_duration, true)
    local vf = string.format(
        "fps=1/%d,scale=%d:%d,tile=%dx%d,format=bgra",
        Thumbnail_interval_in_sec,
        Preview_img_w,
        Preview_img_h,
        Sprite_grid_rows,
        Sprite_grid_cols
    )
    local t1 = os.time()
    -- @todo: Optimise further by generating multi sprite sheet paralelly using "ss -i"
    mp.command_native_async({
            name = "subprocess",
            playback_only = false,
            capture_stdout = true,
            args = { "ffmpeg", "-hide_banner", "-loglevel", "panic", "-i", filepath, "-vf", vf, "-fps_mode", "passthrough", "-f", "rawvideo", Sprite_sheet_name, "-y" },
        },
        function()
            Generating_sprite = false
            print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")
            local t2 = os.time()
            local time_dif = os.difftime(t2, t1)
            Main_sprite = io.open(Sprite_sheet_name, "rb")
            if Main_sprite then
                Sprite_generated = true
            end
            local message = string.format("Finished generating sprite in %d seconds", time_dif)
            helper.showMessage(message, opts.message_duration, true)
            print("@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@")
        end
    )
end

local function on_playback_start()
    local filename = mp.get_property("filename")
    local filepath = mp.get_property("path")
    if filepath then
      print("filepath: " .. filepath)
  end

    Platform = mp.get_property("platform")
    print("Platform: " .. Platform)

    Cache_dir = helper.getCacheDir()
    print("Cache directory: " .. Cache_dir)

    -- local sprite_name = string.format("%s-sprite.bgra", filename)
    Sprite_sheet_name = helper.joinPath(Cache_dir, ("%s-sprite.bgra"):format(filename))

    -- local temp_prev_name = string.format("%s-temp.bgra", filename)
    Temp_prev_name = helper.joinPath(Cache_dir, ("%s-temp.bgra"):format(filename))

    -- Reset state for new file
    Sprite_generated = false
    Generating_sprite = false
    if Main_sprite then Main_sprite:close() end
    Main_sprite = nil

    helper.showMessage("Beginning mpv-seekpeek magic ----------------^^", opts.message_duration, true)

    Main_sprite = io.open(Sprite_sheet_name, "rb")
    if Main_sprite then
      local size = Main_sprite:seek("end")
      if size and size > 0 then
          Main_sprite:seek("set", 0)
          Sprite_generated = true
          helper.showMessage("Pre-generated sprite found, ready for preview", opts.message_duration, true)
      else
          Main_sprite:close()
          Main_sprite = nil
      end
    end

    if not Sprite_generated then
       if opts.auto_start then
         generate_sprite()
       else
           helper.showMessage("Press " .. opts.key_generate .. " to generate sprite sheet", opts.message_duration, true)
       end
  end

    if opts.auto_fullscreen then
        mp.set_property("fullscreen", "yes")
    end
end


-- Delete temp prev file on playback end
local function on_playback_end()
    if Main_sprite then Main_sprite:close() end
    Main_sprite = nil
    Sprite_generated = false
    os.remove(Temp_prev_name)
    if opts.delete_sprite_on_exit and Sprite_sheet_name ~= "" then
        os.remove(Sprite_sheet_name)
        print("Deleted sprite sheet: " .. Sprite_sheet_name)
    end
end

mp.register_event("start-file", on_playback_start)
mp.register_event("end-file", on_playback_end)

-- Recalculate seekbar position whenever OSD dimensions change (covers the initial load, fullscreen toggle, window resize, etc.)
mp.observe_property("osd-dimensions", "native", function(_, val)
    if val then CalculateSeekbarPosition() end
end)



--[[
- Function to calculate the seekbar position based on the video dimensions.
- This is necessary because the seekbar position can vary based on the video resolution and aspect ratio.
- The function will be called whenever osd size changes to ensure that the seekbar position is accurate everytime.
- @todo: Check the same with diff screen resolution
- NOTE: preview positioning now adapts using Preview_img_h and fallback positioning
]] --
function CalculateSeekbarPosition()
    Video_width, Video_height = mp.get_osd_size()
    Seekbar_y_start = Video_height * 0.96 -- 96% of vh
    Seekbar_y_end = Video_height
    Seekbar_x_start = Video_width * 0.1828
    Seekbar_x_end = Video_width * 0.6828
    print("Seekbar x: " .. Seekbar_x_start .. " to " .. Seekbar_x_end)
    print("Seekbar y: " .. Seekbar_y_start .. " to " .. Seekbar_y_end)
end

-- Set duration
mp.observe_property("duration", "number", function()
    local value = mp.get_property("duration")
    Duration = tonumber(value)
end)

mp.observe_property("mouse-pos", "native", function(_, pos)
    if not pos or not opts.preview_enabled then
        return
    end
    if Generating_sprite then
        return
    end

    -- NOTE: throttle preview updates to reduce I/O and overlay spam
    local now = mp.get_time()
    if now - last_preview_time < preview_interval then
        return
    end
    last_preview_time = now

    local mouse_x, mouse_y = pos.x, pos.y

    local on_seekbar = mouse_x >= Seekbar_x_start
        and mouse_x <= Seekbar_x_end
        and mouse_y >= Seekbar_y_start
        and mouse_y <= Seekbar_y_end

    -- Hide preview if not on seekbar
    if not on_seekbar then
        if preview_visible then
            mp.commandv("overlay_remove", Last_overlay_id)
            preview_visible = false
        end
        return
    end

    if not (Sprite_generated and Duration and Duration > 0) then
        return
    end

    local relative_x = (mouse_x - Seekbar_x_start) / (Seekbar_x_end - Seekbar_x_start)
    relative_x = math.max(0, math.min(1, relative_x))

    local timestamp = relative_x * Duration
    local overlay_x, overlay_y = GetOverlayPosition(mouse_x)

    if GetPreviewFromSpriteSheet(timestamp) then
        ShowPreviewOverlay(overlay_x, overlay_y)
    end
end)

-- NOTE: dynamic offset based on preview size + fallback if off-screen
-- Function to get overlay postion
function GetOverlayPosition(x)
	local margin = 20
	local y = Seekbar_y_start - (Preview_img_h + margin)

	-- If it would go off-screen, place it below instead
	if y < 0 then
		y = Seekbar_y_end + margin
	end

	return math.floor(x - Preview_img_w / 2), math.floor(y)
end

function ShowPreviewOverlay(x, y)
    mp.command_native_async({
        name = "overlay_add",
        id = Last_overlay_id,
        x = x,
        y = y,
        offset = 0,
        fmt = "bgra",
        file = Temp_prev_name,
        w = Preview_img_w,
        h = Preview_img_h,
        stride = 4 * Preview_img_w,
    }, function()
      preview_visible = true
      --- Uncomment if debugging
      --  print("Shown overlay")
    end)
end

function GetPreviewFromSpriteSheet(timestamp)
    if not Main_sprite then
        Main_sprite = io.open(Sprite_sheet_name, "rb")
        if not Main_sprite then
            return false
        end
    end

    local tile_index = math.floor(timestamp / Thumbnail_interval_in_sec)
    local max_tiles = Sprite_grid_rows * Sprite_grid_cols
    -- NOTE: Guard corrupt previews, crashes or the OoB-reads hard limit issue
    if tile_index >= max_tiles then
        return false
    end

    local full_w = Preview_img_w * Sprite_grid_cols
    local full_stride = full_w * 4

    local row_num = math.floor(tile_index / Sprite_grid_cols)
    local col_num = tile_index % Sprite_grid_cols

    local y_off = row_num * Preview_img_h
    local x_off = col_num * Preview_img_w
    local byte_start = y_off * full_stride + x_off * 4

    -- TODO(original): load only needed sprite rows to reduce memory usage
    -- NOTE: current implementation reads full rows but slices needed region

    local temp = io.open(Temp_prev_name, "wb")
    if not temp then
        return false
    end

    for i = 0, Preview_img_h - 1 do
        local row_byte_start = byte_start + (i * full_stride)

        local ok = pcall(function()
            Main_sprite:seek("set", row_byte_start)
        end)
        if not ok then
            temp:close()
            return false
        end

        local full_row_data = Main_sprite:read(full_stride)
        if not full_row_data or #full_row_data ~= full_stride then
            temp:close()
            return false
        end

        local start = x_off * 4 + 1
        local stop  = (x_off + Preview_img_w) * 4
        temp:write(string.sub(full_row_data, start, stop))
    end

    temp:close()
    return true
end

-- Keybindings
mp.add_key_binding(opts.key_generate, "seekpeek-generate", function()
    if Sprite_sheet_name == "" then
        mp.osd_message("No file loaded yet")
        return
    end
    generate_sprite()
end)

mp.add_key_binding(opts.key_regenerate, "seekpeek-regenerate", function()
    if Sprite_sheet_name == "" then
        mp.osd_message("No file loaded yet")
        return
    end
    generate_sprite(true)
end)

mp.add_key_binding(opts.key_toggle_preview, "seekpeek-toggle-preview", function()
    opts.preview_enabled = not opts.preview_enabled
    if not opts.preview_enabled then
        mp.commandv("overlay_remove", Last_overlay_id)
    end
    mp.osd_message("Seekpeek preview: " .. (opts.preview_enabled and "ON" or "OFF"))
end)

mp.add_key_binding(opts.key_delete_sprite, "seekpeek-delete-sprite", function()
    if Sprite_sheet_name == "" then
        mp.osd_message("No sprite to delete")
        return
    end
    if Main_sprite then Main_sprite:close() end
    Main_sprite = nil
    Sprite_generated = false
    mp.commandv("overlay_remove", Last_overlay_id)
    local ok = os.remove(Sprite_sheet_name)
    if ok then
        mp.osd_message("Deleted sprite: " .. Sprite_sheet_name)
    else
        mp.osd_message("No sprite file found to delete")
    end
end)
