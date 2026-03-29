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
Last_overlay_id = math.random(0, 63)
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
        os.remove(Sprite_sheet_name)
        mp.commandv("overlay_remove", Last_overlay_id)
    end

    -- Check if sprite already exists
    Main_sprite = io.open(Sprite_sheet_name, "rb")
    if Main_sprite and Main_sprite:seek("end") > 0 then
        Sprite_generated = true
        helper.showMessage("Pre-generated sprite found, ready for preview", opts.message_duration, true)
        return
    end

    if not helper.isFFmpegAvailable() then
        local error_message = "Unable to find ffmpeg. Please install/add it to your PATH to use the script."
        helper.showMessage(error_message, opts.message_duration, true)
        return
    end

    Generating_sprite = true
    helper.showMessage("Generating sprite sheet...", opts.message_duration, true)
    -- @todo: Generate sprite sheet based on the aspect ratio of the video so as to not fill up sprite with empty pads
    local vf = string.format(
        "fps=1/%d,scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:((ow-iw)/2):((oh-ih)/2):color=black,tile=%dx%d,format=bgra",
        Thumbnail_interval_in_sec,
        Preview_img_w,
        Preview_img_h,
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
        function(val, suc, err)
            Generating_sprite = false
            print("@@@@@@@@@@@@@@@@@@@@@")
            local t2 = os.time()
            local time_dif = os.difftime(t2, t1)
            Main_sprite = io.open(Sprite_sheet_name, "rb")
            if Main_sprite then
                Sprite_generated = true
            end
            local message = string.format("Finished generating sprite in %d seconds", time_dif)
            helper.showMessage(message, opts.message_duration, true)
            print("@@@@@@@@@@@@@@@@@@@@@")
        end
    )
end

local function on_playback_start()
    local filename = mp.get_property("filename")
    local filepath = mp.get_property("path")
    print("filepath: " .. filepath)

    Platform = mp.get_property("platform")
    print("Platform: " .. Platform)

    Cache_dir = helper.getCacheDir()
    print("Cache directory: " .. Cache_dir)

    local sprite_name = string.format("%s-sprite.bgra", filename)
    Sprite_sheet_name = helper.joinPath(Cache_dir, sprite_name)

    local temp_prev_name = string.format("%s-temp.bgra", filename)
    Temp_prev_name = helper.joinPath(Cache_dir, temp_prev_name)

    -- Reset state for new file
    Sprite_generated = false
    Generating_sprite = false
    if Main_sprite then Main_sprite:close() end
    Main_sprite = nil

    helper.showMessage("Beginning mpv-seekpeek magic ----------------^^", opts.message_duration, true)

    Main_sprite = io.open(Sprite_sheet_name, "rb")
    if Main_sprite and Main_sprite:seek("end") > 0 then
        Main_sprite:seek("set", 0)
        Sprite_generated = true
        helper.showMessage("Pre-generated sprite found, ready for preview", opts.message_duration, true)
    elseif opts.auto_start then
        if Main_sprite then Main_sprite:close() end
        Main_sprite = nil
        generate_sprite()
    else
        if Main_sprite then Main_sprite:close() end
        Main_sprite = nil
        helper.showMessage("Press " .. opts.key_generate .. " to generate sprite sheet", opts.message_duration, true)
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
    if not pos then return end

    mp.commandv("overlay_remove", Last_overlay_id);

    if not opts.preview_enabled then return end
    local mouse_x, mouse_y = pos.x, pos.y
    if mouse_x >= Seekbar_x_start and mouse_x <= Seekbar_x_end and mouse_y >= Seekbar_y_start and mouse_y <= Seekbar_y_end then
        print("Mouse is on the seekbar area: " .. mouse_x .. " - " .. mouse_y)
        --[[
            * Find the timestamp of the video based on the mouse position on the seekbar. Steps below:
            * Get the image file,
            * Show the preview
            * hide the preview on x change
        ]]
        -- @todo: Also only do this if diff bw currentx and last x is more than 5?
        if (Sprite_generated and Duration and Duration > 0) then
            local relative_x = (mouse_x - Seekbar_x_start) / (Seekbar_x_end - Seekbar_x_start)
            local timestamp = relative_x * Duration
            Last_overlay_id = 5
            local overlay_x, overlay_y = GetOverlayPosition(mouse_x)

            local res = GetPreviewFromSpriteSheet(timestamp)
            if (res) then
                ShowPreviewOverlay(overlay_x, overlay_y)
            else
                helper.showMessage("Error extracting preview tile", opts.message_duration, true)
            end
        end
    end
end)

-- Function to get overlay postion
function GetOverlayPosition(x)
    return math.floor(x - Preview_img_w / 2), math.floor(Seekbar_y_start - 150)
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
    }, function() print("Shown overlay") end)
end

function GetPreviewFromSpriteSheet(timestamp)
    -- local tile_index = timestamp % (Sprite_grid_rows * Sprite_grid_cols)
    local tile_index = math.floor(timestamp / Thumbnail_interval_in_sec)
    local full_w = Preview_img_w * Sprite_grid_cols     -- 240 * 20 = 4800
    local full_h = Preview_img_h * Sprite_grid_rows     -- 100 * 20 = 2000
    local bytes_per_pixel = 4                           -- BGRA standard (yeah its heavy)
    local full_stride = full_w * bytes_per_pixel        -- 19200 (stride size is usually 4 x width as per mpv doc)
    local tile_stride = Preview_img_w * bytes_per_pixel -- 960

    -- Find the row and column
    local row_num = math.floor(tile_index / Sprite_grid_cols)
    local col_num = tile_index % Sprite_grid_cols

    -- Byte offset to top-left of tile
    local y_off = row_num * Preview_img_h -- pixel y
    local x_off = col_num * Preview_img_w -- pixel x
    local byte_start = y_off * full_stride + x_off * bytes_per_pixel

    -- @todo: Only load a single row of the sprite sheet at a time to reduce memory usage and speed up processing.
    if not Main_sprite then
        helper.showMessage("Error: Could not open " .. Sprite_sheet_name, opts.message_duration, true)
        return false
    end

    local temp = io.open(Temp_prev_name, "wb")
    if not temp then
        helper.showMessage("Error: Could not open " .. Temp_prev_name, opts.message_duration, true)
        Main_sprite:close()
        return false
    end

    -- Extract 100 rows
    for i = 0, Preview_img_h - 1 do
        local row_byte_start = byte_start + (i * full_stride)
        Main_sprite:seek("set", row_byte_start)
        local full_row_data = Main_sprite:read(full_stride)
        if #full_row_data ~= full_stride then
            helper.showMessage("Error: Incomplete row read at row " .. (y_off + i), opts.message_duration, true)
            break
        end
        local tile_row_data = string.sub(full_row_data, x_off * bytes_per_pixel + 1,
            (x_off + Preview_img_w) * bytes_per_pixel)
        temp:write(tile_row_data)
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
    local ok, err = os.remove(Sprite_sheet_name)
    if ok then
        mp.osd_message("Deleted sprite: " .. Sprite_sheet_name)
    else
        mp.osd_message("No sprite file found to delete")
    end
end)
