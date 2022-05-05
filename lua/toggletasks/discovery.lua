local M = {}

local Path = require('plenary.path')
local Task = require('toggletasks.task')
local utils = require('toggletasks.utils')
local config = require('toggletasks.config')

-- Find candidate configuration directories for given/current window
function M.config_dirs(opts)
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

    dirs = utils.unique(dirs)
    utils.debug('discovery.config_dirs: %s', vim.inspect(vim.tbl_map(utils.short_path, dirs)))

    return dirs
end

-- Find available configuration files for given/current window
function M.config_files(opts)
    local dirs = M.config_dirs(opts)

    -- Collect all config files
    local files = {}
    for _, dir in ipairs(dirs) do
        dir = Path:new(dir)
        for _, path in ipairs(config.search_paths) do
            local file = dir / path
            if file:exists() then
                table.insert(files, file:absolute())
            end
        end
    end

    return files
end

-- Find all tasks for given/current window
function M.tasks(opts)
    local files = M.config_files(opts)

    -- Create tasks
    local tasks = {}
    for _, file in ipairs(files) do
        local found = Task:from_config(file) or {}
        utils.debug('discover: found %d tasks in file: %s', #found, utils.short_path(file))
        vim.list_extend(tasks, found)
    end
    utils.debug('discover: found %d tasks in total', #tasks)

    return tasks
end

return M
