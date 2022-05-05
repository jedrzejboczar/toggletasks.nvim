local Path = require('plenary.path')
local terminal = require('toggleterm.terminal')
local Terminal = require('toggleterm.terminal').Terminal
local utils = require('toggletasks.utils')
local config = require('toggletasks.config')

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

local function load_config(file)
    local path = Path:new(file)
    if not path:exists() then
        utils.warn('Config file does not exist: %s', path:absolute())
        return
    end

    local content = vim.F.npcall(path.read, path)
    if not content then
        utils.warn('Could not read task config: %s', path:absolute())
        return
    end

    local config = vim.F.npcall(vim.json.decode, content)
    if not config then
        utils.warn('Invalid tasks config format: %s', path:absolute())
        return
    end

    utils.debug('load_config: loaded: %s', utils.short_path(file))

    return config
end

-- Extract tasks from a JSON config file
function Task:from_config(config_file)
    config_file = Path:new(config_file)
    local config = load_config(config_file)
    if not config then return end

    local tasks = {}
    for i, task_conf in ipairs(config.tasks or {}) do
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

local function expand_vars(s, vars)
    for var, value in pairs(vars) do
        s = s:gsub('${' .. var .. '}', value)
    end
    return s
end

-- Expand environmental variables and special task-related variables in a string.
-- Requires explicit syntax with curly braces, e.g. "${VAR}".
function Task:_expand(str, win, opts)
    opts = vim.tbl_extend('force', {
        env = true
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
        file_ext = vim.fn.fnamemodify(filename, ':e'),
        file_tail = vim.fn.fnamemodify(filename, ':p:t'),
        file_head = vim.fn.fnamemodify(filename, ':p:h'),
    }

    -- Expand special variables
    str = expand_vars(str, vars)

    -- Expand environmental variables
    if opts.env then
        str = expand_vars(str, vim.fn.environ())
    end

    return str
end

function Task:expand_cwd(win)
    -- Use fnamemodify to make sure ~/ is expanded
    return self.config.cwd and vim.fn.fnamemodify(self:_expand(self.config.cwd, win), ':p')
end

function Task:expand_env(win)
    if not self.config.env then return end
    local env = {}
    for key, val in pairs(self.config.env) do
        env[key] = self:_expand(val, win)
    end
    return env
end

function Task:expand_cmd(win)
    return self:_expand(self.config.cmd, win, { env = false })
end

-- Kill a running task
function Task:shutdown()
    if self.term then
        self.term:shutdown()
        terminal.delete(self.term.id)
        self.term = nil
    end
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
            running[id] = nil
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
        running[id] = nil
    end
end

-- Add a task to the list
function Task.add(task)
    running[task:id()] = task
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

function Task:is_running()
    return Task.get(self:id()) ~= nil
end

return Task
