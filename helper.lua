local helper = {}

local mp = require("mp")
local utils = require("mp.utils")

-- Normalize path using mpv's built-in normalize-path
function helper.normalizePath(path)
    return mp.command_native({ "normalize-path", path })
end

-- Join path components and normalize for the current platform
function helper.joinPath(base, name)
    return helper.normalizePath(utils.join_path(base, name))
end

-- Get the cache directory path
function helper.getCacheDir()
    return helper.normalizePath(mp.command_native({ "expand-path", "~~cache/" }))
end

-- Check if ffmpeg is available in the system
function helper.isFFmpegAvailable()
    local result = mp.command_native({ name = "subprocess", args = { "ffmpeg", "-version" }, capture_stdout = true, playback_only = false })
    return result and result.status == 0
end

-- Display a message on the OSD and optionally print to console for debugging
function helper.showMessage(msg, duration, debug)
    mp.osd_message(msg, duration)
    if debug then
        print(msg)
    end
end

return helper
