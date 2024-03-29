local M = {}

-- Use a function to always get a new table, even if some deep field is modified,
-- like `config.commands.save = ...`. Returning a "constant" still seems to allow
-- the LSP completion to work.
local function defaults()
    -- stylua: ignore
    return {
        debug = false,
        silent = false,
        short_paths = true,
        search_paths = {
            'toggletasks',
            '.toggletasks',
            '.nvim/toggletasks',
        },
        scan = {
            global_cwd = true,
            tab_cwd = true,
            win_cwd = true,
            lsp_root = true,
            dirs = {},
            rtp = false,
            rtp_ftplugin = false,
        },
        tasks = {},
        lsp_priorities = {
            ['null-ls'] = -10,
        },
        toggleterm = {
            close_on_exit = false,
            hidden = true,
        },
        telescope = {
            spawn = {
                open_single = true,
                show_running = false,
                mappings = {
                    select_float = '<C-f>',
                    spawn_smart = '<C-a>',
                    spawn_all = '<M-a>',
                    spawn_selected = nil,
                },
            },
            select = {
                mappings = {
                    select_float = '<C-f>',
                    open_smart = '<C-a>',
                    open_all = '<M-a>',
                    open_selected = nil,
                    kill_smart = '<C-q>',
                    kill_all = '<M-q>',
                    kill_selected = nil,
                    respawn_smart = '<C-s>',
                    respawn_all = '<M-s>',
                    respawn_selected = nil,
                },
            },
        },
    }
end

local config = defaults()

function M.setup(opts)
    local new_config = vim.tbl_deep_extend('force', {}, defaults(), opts or {})
    -- Do _not_ replace the table pointer with `config = ...` because this
    -- wouldn't change the tables that have already been `require`d by other
    -- modules. Instead, clear all the table keys and then re-add them.
    for _, key in ipairs(vim.tbl_keys(config)) do
        config[key] = nil
    end
    for key, val in pairs(new_config) do
        config[key] = val
    end
end

-- Return the config table (getting completion!) but fall back to module methods.
return setmetatable(config, { __index = M })
