local M = {}

local config = require('toggletasks.config')

function M.debug(...)
    if config.debug then
        local args = { ... }
        -- TODO: test version with a function
        if type(args[1]) == 'function' then
            args = args[1](select(2, ...))
        end
        vim.notify(string.format(unpack(args)), vim.log.levels.DEBUG)
    end
end

function M.info(...)
    if not config.silent then
        vim.notify(string.format(...))
    end
end

function M.warn(...)
    vim.notify(string.format(...), vim.log.levels.WARN)
end

function M.error(...)
    vim.notify(string.format(...), vim.log.levels.ERROR)
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
        tab = vim.fn.getcwd(-1, vim.api.nvim_win_get_tabpage(win)),
        global = vim.fn.getcwd(-1, -1),
        lsp = M.get_lsp_roots(vim.api.nvim_win_get_buf(win)),
    }
end

function M.split_lines(s, trimempty)
    return vim.split(s, '\n', { plain = true, trimempty = trimempty })
end

return M
