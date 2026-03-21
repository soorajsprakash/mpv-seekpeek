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
Temp_prev_name = "temp.bgra"
Sprite_grid_rows = 15
Sprite_grid_cols = 10
Preview_img_w = 240
Preview_img_h = 100
Thumbnail_interval_in_sec = 5
Sprite_generated = false
Platform = nil
Main_sprite = 5
Total_sprite_parts = 0
Sprites = {}

local function on_playback_start()
    local filename = mp.get_property("filename")
    print(filename)

    Platform = mp.get_property("platform")
    print(Platform)
    Cache_dir = helper.getCacheDir()
    print(Cache_dir)

    local sprite_name = string.format("/%s-sprite.bgra", filename)
    Sprite_sheet_name = Cache_dir .. sprite_name

    local temp_prev_name = string.format("/%s-temp.bgra", filename)
    -- Temp_prev_name = Cache_dir .. temp_prev_name

    print("Beginning script----------------^^")
    local vf = string.format(
        "fps=1/%d,scale=%d:%d,tile=%dx%d,format=bgra",
        Thumbnail_interval_in_sec,
        Preview_img_w,
        Preview_img_h,
        Sprite_grid_cols,
        Sprite_grid_rows
    )
    local t1 = os.time()
    -- Generate sprite sheet only if it doesnt exists
    -- Main_sprite = io.open(Sprite_sheet_name, "rb")
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
                args = {
                    "ffmpeg",
                    "-hide_banner",
                    "-loglevel", "panic",
                    "-i", filename,
                    "-vf", vf,
                    "-fps_mode", "passthrough",
                    "-start_number", "0",
                    -- "-f", "rawvideo",
                    "-f", "image2",
                    "-pix_fmt", "bgra",
                    "sprite_%d.bgra",
                    "-y"
                },
            },
            function(val, suc, err)
                print("@@@@@@@@@@@@@@@@@@@@@")
                local t2 = os.time()
                local time_dif = os.difftime(t2, t1)
                Sprite_generated = true
                local message = string.format("Finished generating sprite in %d seconds", time_dif)
                print(message)
                mp.osd_message(message)
                print("@@@@@@@@@@@@@@@@@@@@@")
                CacheSpritesInMemory()
            end
        )
    else
        print("Pre generated sprite found")
        Sprite_generated = true
        -- CacheSpritesInMemory()
    end

    -- Set fullscreen
    mp.set_property("fullscreen", "yes")
end

function CacheSpritesInMemory()
    print("Total_sprite_parts: " .. Total_sprite_parts)
    for i = 0, Total_sprite_parts - 1 do
        local name = string.format("sprite_%d.bgra", i)
        print("[[ name ]]: " .. name)

        local f = io.open(name, "rb")
        if not f then
            print("Failed to open sprite:", name)
        else
            Sprites[i] = f
        end
    end
    print("Caching donee.................................")
end
-- Delete temp prev file on playback end
-- @todo: also to be done when player quit
local function on_playback_end()
    -- if Main_sprite then Main_sprite:close() end
    -- os.remove(Temp_prev_name)
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
    if Duration then
        print("Duration: " .. Duration .. " s")
        Total_sprite_parts = math.ceil(Duration / (Thumbnail_interval_in_sec * Sprite_grid_rows * Sprite_grid_cols))
        print("Total sprite parts needed: " .. Total_sprite_parts)
        if Sprite_generated then
            CacheSpritesInMemory()
            print("%%%%%%%%%%%%%%%")
            for index, res in ipairs(Sprites) do
                print("i: " .. index)
                print(res)
            end
            print("%%%%%%%%%%%%%%%")
        end
    end
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
        if (Sprite_generated and Duration and Duration > 0) then
            local relative_x = (mouse_x - Seekbar_x_start) / (Seekbar_x_end - Seekbar_x_start)
            local timestamp = relative_x * Duration
            Last_overlay_id = 5
            local overlay_x, overlay_y = GetOverlayPosition(mouse_x)

            local res = GetPreviewTileData(timestamp)
            print("************")
            print(res)
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


--[[
* Function to get the preview tile from the sprite sheet based on the timestamp.
* Steps:
* Calculate the sprite index/name based on the timestamp and thumbnail interval
* Calculate the row and column number based on the tile index and sprite grid configuration
]]
function CalculatePreviewDataPosition(timestamp)
    local global_index = math.floor(timestamp / Thumbnail_interval_in_sec) -- new
    local sprite_index = math.floor(global_index / (Sprite_grid_rows * Sprite_grid_cols))
    local local_index  = global_index % (Sprite_grid_rows * Sprite_grid_cols)
    local row          = math.floor(local_index / Sprite_grid_cols)
    local col          = math.floor(local_index % Sprite_grid_cols)
    local x_pos        = col * Preview_img_w
    local y_pos        = row * Preview_img_h
    print("sprite index: " .. sprite_index)
    print("x position: " .. x_pos)
    print("y position: " .. y_pos)
    return {
        x_pos = x_pos,
        y_pos = y_pos,
        row = row,
        col = col,
        sprite_index = sprite_index,
    }
end

function GetPreviewTileData(timestamp)
    local prev_data = CalculatePreviewDataPosition(timestamp)
    local sprite_index = prev_data.sprite_index
    local sprite_name = string.format("sprite_%d.bgra", sprite_index)
    print("Sprite_name: " .. sprite_name)
    local temp = io.open(Temp_prev_name, "wb")
    if not temp then
        print("Error: Could not open " .. Temp_prev_name)
        return false
    end

    local x_off = prev_data.col * Preview_img_w
    local y_off = prev_data.row * Preview_img_h
    local full_w = Preview_img_w * Sprite_grid_cols

    local bytes_per_pixel = 4                    -- BGRA standard (yeah its heavy)
    local full_stride = full_w * bytes_per_pixel -- 19200 (stride size is usually 4 x width as per mpv doc)
    local row_bytes = Preview_img_w * bytes_per_pixel
    local byte_start = y_off * full_stride

    print("//////////////////////////////////////////////////////////")
    for i = 0, Preview_img_h - 1 do
        local row_start = byte_start + (i * full_stride)
        print("row_start: " .. row_start)
        local pixel_start = row_start + x_off * bytes_per_pixel
        print("pixel_start: " .. pixel_start)


        Sprites[sprite_index]:seek("set", pixel_start)
        local tile_row = Sprites[sprite_index]:read(row_bytes)

        if not tile_row or #tile_row ~= row_bytes then
            print("Error: Incomplete row read")
            break
        end
        temp:write(tile_row)
    end

    temp:close()

end

