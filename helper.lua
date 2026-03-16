local helper = {}

local mp = require("mp")

function helper.getCacheDir()
    return mp.command_native({ "expand-path", "~~cache/" })
end

return helper
