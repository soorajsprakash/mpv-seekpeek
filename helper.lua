local helper = {}

local mp = require("mp")
local utils = require("mp.utils")

-- Get the cache directory path
function helper.getCacheDir()
    return mp.command_native({ "expand-path", "~~cache/" })
end

-- Check if ffmpeg is available in the system
function helper.isFFmpegAvailable()
    local result = mp.command_native({ name = "subprocess", args = { "ffmpeg", "-version" }, capture_stdout = true })
    return result and result.status == 0
end
return helper
