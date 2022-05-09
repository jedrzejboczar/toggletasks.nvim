local Path = require('plenary.path')
local terminal = require('toggleterm.terminal')
local Terminal = require('toggleterm.terminal').Terminal
local utils = require('toggletasks.utils')
local config = require('toggletasks.config')
local loader = require('toggletasks.loader')

local Task = {}
Task.__index = Task

-- Create new task from task configuration
--@param conf table: table in the same format as in JSON['tasks'][x]
--@param config_file string?: path to config file, or nil if defined from lua
function Task:new(conf, config_file)
    vim.validate {
        name = { conf.name, 'string' }, -- descriptive name for the task
        -- TODO: remove id
        id = { conf.id, { 'string', 'nil' } }, -- used to uniquely identify task, if nil then name is used
        cmd = { conf.cmd, 'string' }, -- command to run TODO: support tables (requires toggleterm support)
        cwd = { conf.cwd, { 'string', 'nil' } }, -- task working directory
        tags = { conf.tags, { 'string', 'table', 'nil' } }, -- tags used to filter tasks
        env = { conf.env, { 'table', 'nil' } }, -- environmental variables passed to jobstart()
        clear_env = { conf.clear_env, { 'boolean', 'nil' } }, -- passed to jobstart()
        close_on_exit = { conf.close_on_exit, { 'boolean', 'nil' } }, -- Terminal.close_on_exit
        hidden = { conf.hidden, { 'boolean', 'nil' } }, -- Terminal.hidden
        count = { conf.count, { 'number', 'nil' } }, -- Terminal.count
        config_file = { config_file, { 'string', 'nil' } }, -- path to config file (if loaded from file)
    }
    -- Prevent empty dict which will cause errors when passed to jobstart
    local env = conf.env
    if env and #vim.tbl_keys(env) == 0 then
        env = nil
    end
    return setmetatable({
        config = {
            name = conf.name,
            id = conf.id or conf.name,
            cmd = conf.cmd,
            cwd = conf.cwd,
            tags = utils.as_table(conf.tags or {}),
            env = env,
            clear_env = conf.clear_env,
            close_on_exit = vim.F.if_nil(conf.close_on_exit, config.defaults.close_on_exit),
            hidden = vim.F.if_nil(conf.hidden, config.defaults.hidden),
            count = conf.count,
        },
        config_file = config_file,
        term = nil,
    }, self)
end

-- Extract tasks from a JSON config file
function Task:from_config(config_file)
    config_file = Path:new(config_file)
    local conf = loader.load_config(config_file)
    if not conf then
        return
    end

    local tasks = {}
    for i, task_conf in ipairs(conf.tasks or {}) do
        utils.debug('from_config: parsing %d: %s', i, vim.inspect(task_conf))
        local ok, task_or_err = pcall(Task.new, Task, task_conf, config_file:absolute())
        if ok then
            table.insert(tasks, task_or_err)
        else
            utils.error('Invalid task %d in config "%s": %s', i, config_file:absolute(), task_or_err)
        end
    end
    return tasks
end

-- Expand "${something}" but not "$${something}"
local function expand_vars(s, handler)
    local parts = {}
    local start = 0
    while true do
        local left = s:find('%${', start + 1)
        -- No next expansion - add remaining string and break
        if left == nil then
            table.insert(parts, s:sub(start + 1))
            break
        end

        local prev_char = s:sub(left - 1, left - 1)
        -- If user escaped the expansion ("$${...}") than replace $$ with $
        if prev_char == '$' then
            -- "string $${escaped}"
            -- +-------+ +--------
            --  insert   start
            table.insert(parts, s:sub(start + 1, left - 1))
            start = left
        else
            -- Unescaped expansion, first insert text before
            table.insert(parts, s:sub(start + 1, left - 1))

            -- Find expansion end
            local right = s:find('}', left + 2)
            if not right then
                -- Avoid assertion by returning unescaped value
                utils.error('Missing closing bracket when expanding: "%s"', s)
                return s
            end

            -- Expand
            local inner = s:sub(left + 2, right - 1)
            local expansion = handler(inner)
            if not expansion then
                expansion = ''
                utils.warn('Unknown expansion variable "%s"', inner)
            end
            table.insert(parts, expansion)
            start = right
        end
    end
    utils.debug('expand_vars: "%s" -> %s', s, vim.inspect(parts))
    return table.concat(parts, '')
end

-- Expand environmental variables and special task-related variables in a string.
-- Requires explicit syntax with curly braces, e.g. "${VAR}".
-- Can be escaped via "$$", e.g. "$${VAR}" will be expanded to "${VAR}".
-- Supports fnamemodify modifiers e.g. "${VAR:t:r}" (see |filename-modifiers|).
function Task:_expand(str, win, opts)
    opts = vim.tbl_extend('force', {
        env = true,
    }, opts or {})

    win = win or vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    local filename = vim.api.nvim_buf_get_name(buf)

    local dirs = utils.get_work_dirs(win)

    local vars = {
        -- Expands to directory of config file if exists
        config_dir = self.config_file and Path:new(self.config_file):parent():absolute(),
        -- Expands to root directory of LSP client with highest priority
        lsp_root = dirs.lsp,
        -- Expand vim cwd types
        win_cwd = dirs.win,
        tab_cwd = dirs.tab,
        global_cwd = dirs.global,
        -- Expand current file
        file = vim.fn.fnamemodify(filename, ':p'),
        -- Leave for backwards compatibility, though these can be achieved by e.g. "${file:p:t}"
        file_ext = vim.fn.fnamemodify(filename, ':e'),
        file_tail = vim.fn.fnamemodify(filename, ':p:t'),
        file_head = vim.fn.fnamemodify(filename, ':p:h'),
    }

    local expand = function(var)
        -- Check filename modifiers
        local colon = var:find(':')
        local mods
        if colon then
            mods = var:sub(colon)
            var = var:sub(1, colon - 1)
        end

        -- Expand special variables
        local s = vars[var]
        -- Expand environmental variables
        if not s and opts.env then
            s = vim.fn.environ()[var]
        end

        -- Apply modifiers
        if mods then
            s = vim.fn.fnamemodify(s, mods)
        end

        return s
    end

    return expand_vars(str, expand)
end

function Task:expand_cwd(win)
    -- Use fnamemodify to make sure ~/ is expanded
    return self.config.cwd and vim.fn.fnamemodify(self:_expand(self.config.cwd, win), ':p')
end

function Task:expand_env(win)
    if not self.config.env then
        return
    end
    local env = {}
    for key, val in pairs(self.config.env) do
        env[key] = self:_expand(val, win)
    end
    return env
end

function Task:expand_cmd(win)
    return self:_expand(self.config.cmd, win, { env = false })
end

-- Assume that tasks are uniquely identified by config_file + name
function Task:id()
    return (self.config_file or '') .. '#' .. self.config.name
end

local running = {}

-- Get a running task by ID if it exists, else return nil
function Task.get(id)
    local task = running[id]
    if task then
        -- Check if the buffer is still valid. It's better to check task buffer,
        -- because toggleterm.terminal.get(id) will not show the task after the
        -- job exit, because it deletes task on TermClose, but we actually want
        -- to have a task as "running" even after exit, so that user can open
        -- taks buffer and see the error message.
        if vim.api.nvim_buf_is_valid(task.term.bufnr) then
            return task
        else
            -- Clean up our list of running tasks
            utils.debug('Task.get: clean up: %s', id)
            task:shutdown()
        end
    end
end

-- Get a list of all running tasks
function Task.get_all()
    -- Make sure to call get() on all tasks to delete them if they have been stopped.
    local tasks = {}
    for _, task in pairs(running) do
        task = Task.get(task:id())
        if task then
            table.insert(tasks, task)
        end
    end
    return tasks
end

-- Delete a running task by ID if it exists
function Task.delete(id)
    local task = Task.get(id)
    if task then
        utils.debug('Task.delete: %s', id)
        task:shutdown()
    end
end

-- Add a task to the list
function Task.add(task)
    running[task:id()] = task
end

-- Kill a running task
function Task:shutdown()
    if self.term then
        self.term:shutdown()
        terminal.delete(self.term.id)
        self.term = nil
        running[self:id()] = nil
    end
end

-- Spawn a task in a terminal
function Task:spawn(win)
    -- Ensure this task is not running
    Task.delete(self:id())

    local opts = {
        cmd = self:expand_cmd(win),
        dir = self:expand_cwd(win),
        close_on_exit = self.config.close_on_exit,
        env = self:expand_env(win),
        clear_env = self.config.clear_env,
        hidden = self.config.hidden,
        count = self.config.count,
    }
    utils.debug('Task:spawn: with opts: %s', vim.inspect(opts))

    self.term = Terminal:new(opts)
    -- Mark the terminal as "ours"
    self.term._task_id = self:id()

    -- Start the terminal job in the background
    self.term:spawn()

    Task.add(self)

    utils.debug('Task:spawn: task "%s" in term "%s"', self:id(), self.term.id)
end

-- Respawn an already running task with the same settings.
-- This re-uses terminal options of the running task (so not expanding based on current window).
function Task:respawn()
    -- Get the actually running task object
    local self = Task.get(self:id())
    if not self then
        utils.error('Task is not running, cannot respawn: "%s"', self.config.name)
        return
    end

    self.term:shutdown()
    utils.debug('Task:respawn: shutdown done')
    vim.schedule(function()
        self.term:spawn()
    end)

    utils.debug('Task:respawn: task "%s" in term "%s"', self:id(), self.term.id)
end

function Task:is_running()
    return Task.get(self:id()) ~= nil
end

return Task
