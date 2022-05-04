local M = {}

local Path = require('plenary.path')
local Task = require('toggletasks.task')
local utils = require('toggletasks.utils')
local config = require('toggletasks.config')

-- Run tasks discovery
function M.discover(opts)
    opts = opts or {}
    local scan = vim.tbl_extend('force', config.scan, opts.scan or {})
    local win = opts.win or vim.api.nvim_get_current_win()

    local work_dirs = utils.get_work_dirs(win)
    local dirs = {}
    vim.list_extend(dirs, scan.dirs)
    if scan.win_cwd then
        table.insert(dirs, work_dirs.win)
    end
    if scan.tab_cwd then
        table.insert(dirs, work_dirs.tab)
    end
    if scan.lsp_root then
        vim.list_extend(dirs, work_dirs.lsp)
    end
    if scan.global_cwd then
        table.insert(dirs, work_dirs.global)
    end

    -- Convert list to a set
    dirs = utils.unique(dirs)
    utils.debug('discover: searching dirs: %s', vim.inspect(dirs))

    -- Collect all configs
    local configs = {}
    for _, dir in ipairs(dirs) do
        dir = Path:new(dir)
        for _, path in ipairs(config.search_paths) do
            local file = dir / path
            if file:exists() then
                table.insert(configs, file)
            end
        end
    end

    -- Create tasks
    local tasks = {}
    for _, conf in ipairs(configs) do
        local found = Task:from_config(conf) or {}
        utils.debug('discover: found %d tasks in file: %s', #found, conf:absolute())
        vim.list_extend(tasks, found)
    end
    utils.debug('discover: found %d tasks total', #tasks)

    return tasks
end

return M
