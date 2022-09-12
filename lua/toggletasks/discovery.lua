local M = {}

local Path = require('plenary.path')
local Task = require('toggletasks.task')
local utils = require('toggletasks.utils')
local config = require('toggletasks.config')
local loader = require('toggletasks.loader')

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

    if scan.rtp then
        vim.list_extend(dirs, vim.api.nvim_get_runtime_file('', true))
    end

    if scan.rtp_ftplugin then
        local buf = vim.api.nvim_win_get_buf(win)
        local ft = vim.api.nvim_buf_get_option(buf, 'filetype')
        if ft ~= '' then
            local glob = string.format('ftplugin/%s', ft)
            vim.list_extend(dirs, vim.api.nvim_get_runtime_file(glob, true))
        end
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
            for _, ext in ipairs(loader.supported_extensions()) do
                local file = dir / (path .. '.' .. ext)
                if file:exists() then
                    table.insert(files, file:absolute())
                end
            end
        end
    end

    return files
end

-- Wrapper around task list allowing for convenient chained filtering
local TaskQuery = {}
TaskQuery.__index = TaskQuery

function TaskQuery:new(tasks)
    return setmetatable(tasks, self)
end

-- Unwrap returning just the internal list without metatable
function TaskQuery:to_list()
    return vim.list_slice(self)
end

-- Filter based on predicate fn(Task) -> boolean
function TaskQuery:filter(fn)
    local tasks = vim.tbl_filter(fn, self)
    return TaskQuery:new(tasks)
end

function TaskQuery:with_tag(tag)
    return self:filter(function(task)
        return vim.tbl_contains(task.config.tags or {}, tag)
    end)
end

function TaskQuery:not_tag(tag)
    return self:filter(function(task)
        return not vim.tbl_contains(task.config.tags or {}, tag)
    end)
end

function TaskQuery:from_file(file)
    return self:filter(function(task)
        if file == nil then
            -- Tasks defined from Lua
            return task.config_file == nil
        else
            -- Tasks defined in files
            return task.config_file and Path:new(task.config_file):absolute() == Path:new(file):absolute()
        end
    end)
end

function TaskQuery:name_matches(pattern)
    return self:filter(function(task)
        return task.config.name:match(pattern)
    end)
end

-- Find all tasks for given/current window, returning a list wrapped in TaskQuery.
-- Can be filtered as `M.tasks():with_tag('dev'):no_tag('build')`
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

    return TaskQuery:new(tasks)
end

return M
