local config = require('toggletasks.config')

local function setup(opts)
    config.setup(opts)
end

return {
    setup = setup,
}
