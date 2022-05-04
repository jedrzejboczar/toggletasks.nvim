local telescope = require('telescope')
local pickers = require('toggletasks.telescope')

return telescope.register_extension {
    exports = {
        spawn = pickers.spawn,
        select = pickers.select,
        -- edit = pickers.edit,
    },
}
