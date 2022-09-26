local M = {}

local Path = require('plenary.path')
local config = require('toggletasks.config')

local function logger(level, notify_fn, cond)
    return function(...)
        if cond and not cond() then
            return
        end
        -- Use notify_fn as string to get correct function if user
        -- replaced it later via vim.notify = ...
        local notify = vim[notify_fn]
        notify(string.format(...), level)
    end
end

local function debug_enabled()
    return config.debug
end

local function info_enabled()
    return not config.silent
end

M.debug = logger(vim.log.levels.DEBUG, 'notify', debug_enabled)
M.debug_once = logger(vim.log.levels.DEBUG, 'notify_once', debug_enabled)
M.info = logger(vim.log.levels.INFO, 'notify', info_enabled)
M.info_once = logger(vim.log.levels.INFO, 'notify_once', info_enabled)
M.warn = logger(vim.log.levels.WARN, 'notify')
M.warn_once = logger(vim.log.levels.WARN, 'notify_once')
M.error = logger(vim.log.levels.ERROR, 'notify')
M.error_once = logger(vim.log.levels.ERROR, 'notify_once')

function M.deprecated(old_name, old_value, new_name, new_value)
    if old_value then
        M.warn_once('toggletasks.nvim: %s is deprecated, use %s', old_name, new_name)
    end
    -- New value overrides the old one
    return new_value or old_value
end

function M.as_table(v)
    return type(v) ~= 'table' and { v } or v
end

function M.not_nil(v)
    return v ~= nil
end

function M.unique(list)
    local set = {}
    return vim.tbl_filter(function(val)
        if not set[val] then
            set[val] = true
            return true
        else
            return false
        end
    end, list)
end

function M.get_lsp_clients(buf)
    buf = buf or vim.api.nvim_get_current_buf()

    -- Need to iterate using pairs()!
    local clients = {}
    for _, client in pairs(vim.lsp.buf_get_clients(buf)) do
        if client.config and client.config.root_dir then
            table.insert(clients, client)
        end
    end

    -- Sort by priority
    local priority = function(client)
        return config.lsp_priorities[client.name] or 0
    end
    table.sort(clients, function(a, b)
        return priority(a) > priority(b)
    end)

    return clients
end

function M.get_lsp_roots(buf)
    return vim.tbl_map(function(client)
        return client.config.root_dir
    end, M.get_lsp_clients(buf))
end

function M.get_work_dirs(win)
    win = win or vim.api.nvim_get_current_win()
    return {
        win = vim.fn.getcwd(win),
        tab = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(vim.api.nvim_win_get_tabpage(win))),
        global = vim.fn.getcwd(-1, -1),
        lsp = M.get_lsp_roots(vim.api.nvim_win_get_buf(win)),
    }
end

function M.split_lines(s, trimempty)
    return vim.split(s, '\n', { plain = true, trimempty = trimempty })
end

function M.short_path(path)
    path = Path:new(path)
    local cwd = Path:new(vim.fn.getcwd()):absolute()
    if config.short_paths and vim.startswith(path:absolute(), cwd) then
        local rel = path:make_relative(cwd)
        if rel:sub(1, 1) ~= '.' and rel:sub(1, 1) ~= '/' then
            rel = './' .. rel
        end
        return rel
    else
        return path:absolute()
    end
end

-- For variables that can be values or functions.
function M.as_function(fn_or_value)
    if type(fn_or_value) == 'function' then
        return fn_or_value
    else
        return function(...)
            return fn_or_value
        end
    end
end

-- Lazily evaluate a function, caching the result of the first call
-- for all subsequent calls ever.
function M.lazy(fn)
    local cached
    return function(...)
        if cached == nil then
            cached = fn(...)
            assert(cached ~= nil, 'lazy: fn returned nil')
        end
        return cached
    end
end

-- Wrap function with time based throttling - will cache results until
-- `timeout` milliseconds since last function call. Note that timestamp
-- does not change until we reach next libuv event loop step.
function M.throttle(fn, timeout)
    local last_time
    local cached
    return function(...)
        -- Recompute
        if not last_time or vim.loop.now() > last_time + timeout then
            cached = fn(...)
            last_time = vim.loop.now()
        end
        return cached
    end
end

return M
