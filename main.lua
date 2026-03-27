local mp = require("mp")
local helper = require("helper")


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
Sprite_grid_rows = 30
Sprite_grid_cols = 30
Preview_img_w = 240
Preview_img_h = 100
Thumbnail_interval_in_sec = 5
Sprite_generated = false
Platform = nil
Main_sprite = nil

local function on_playback_start()
    local filename = mp.get_property("filename")
    local filepath = mp.get_property("path")
    print("filepath: " .. filepath)

    Platform = mp.get_property("platform")
    print(Platform)
    Cache_dir = helper.getCacheDir()
    print(Cache_dir)

    local sprite_name = string.format("%s-sprite.bgra", filename)
    Sprite_sheet_name = helper.joinPath(Cache_dir, sprite_name)

    local temp_prev_name = string.format("%s-temp.bgra", filename)
    Temp_prev_name = helper.joinPath(Cache_dir, temp_prev_name)

    print("Beginning script----------------^^")
    local vf = string.format(
        "fps=1/%d,scale=%d:%d,tile=%dx%d,format=bgra",
        Thumbnail_interval_in_sec,
        Preview_img_w,
        Preview_img_h,
        Sprite_grid_rows,
        Sprite_grid_cols
    )
    local t1 = os.time()
    -- Generate sprite sheet only if it doesnt exists
    Main_sprite = io.open(Sprite_sheet_name, "rb")
    if not Main_sprite then
        if not helper.isFFmpegAvailable() then
            local error_message = "Unable to find ffmpeg. Please install/add it to your PATH to use the script."
            print(error_message)
            mp.osd_message(error_message)
            return nil
        end
        -- @todo: Optimise further by generating multi sprite sheet paralelly using "ss -i"
        mp.command_native_async({
                name = "subprocess",
                playback_only = false,
                capture_stdout = true,
                args = { "ffmpeg", "-hide_banner", "-loglevel", "panic", "-i", filepath, "-vf", vf, "-fps_mode", "passthrough", "-f", "rawvideo", Sprite_sheet_name },
            },
            function(val, suc, err)
                print("@@@@@@@@@@@@@@@@@@@@@")
                local t2 = os.time()
                local time_dif = os.difftime(t2, t1)
                Main_sprite = io.open(Sprite_sheet_name, "rb")
                if Main_sprite then
                    Sprite_generated = true
                end
                local message = string.format("Finished generating sprite in %d seconds", time_dif)
                mp.osd_message(message)
                print("@@@@@@@@@@@@@@@@@@@@@")
            end
        )
    else
        print("Pre generated sprite found")
        Sprite_generated = true
    end

    -- Set fullscreen
    mp.set_property("fullscreen", "yes")
end


-- Delete temp prev file on playback end
-- @todo: also to be done when player quit
local function on_playback_end()
    if Main_sprite then Main_sprite:close() end
    os.remove(Temp_prev_name)
end

mp.register_event("start-file", on_playback_start)
mp.register_event("end-file", on_playback_end)

mp.register_event("playback-restart", function() CalculateSeekbarPosition() end)



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
                mp.osd_message("Error extracting preview tile")
                print("Error extracting preview tile")
            end
        end
    end
end)

-- Function to get overlay postion
function GetOverlayPosition(x)
    return math.floor(x - 120), math.floor(Seekbar_y_start - 150)
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
        print("Error: Could not open " .. Sprite_sheet_name)
        return false
    end

    local temp = io.open(Temp_prev_name, "wb")
    if not temp then
        print("Error: Could not open " .. Temp_prev_name)
        Main_sprite:close()
        return false
    end

    -- Extract 100 rows
    for i = 0, Preview_img_h - 1 do
        local row_byte_start = byte_start + (i * full_stride)
        Main_sprite:seek("set", row_byte_start)
        local full_row_data = Main_sprite:read(full_stride)
        if #full_row_data ~= full_stride then
            print("Error: Incomplete row read at row " .. (y_off + i))
            break
        end
        local tile_row_data = string.sub(full_row_data, x_off * bytes_per_pixel + 1,
            (x_off + Preview_img_w) * bytes_per_pixel)
        temp:write(tile_row_data)
    end

    temp:close()
    return true
end
