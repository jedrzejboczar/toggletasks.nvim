local M = {}

local action_state = require('telescope.actions.state')
local actions = require('telescope.actions')
local conf = require('telescope.config').values
local finders = require('telescope.finders')
local make_entry = require('telescope.make_entry')
local pickers = require('telescope.pickers')
local previewers = require('telescope.previewers')

local Task = require('toggletasks.task')
local discovery = require('toggletasks.discovery')
local utils = require('toggletasks.utils')
local config = require('toggletasks.config')

-- Preview

local function task_display(task)
    local tags = vim.tbl_map(function(tag)
        return '#' .. tag
    end, task.config.tags)
    return task.config.name .. ' | ' .. table.concat(tags, ' ')
end

local function make_task_entry(task)
    local display = task_display(task)
    return {
        value = task,
        display = display,
        ordinal = display,
    }
end

local function task_previewer(opts)
    return previewers.new_buffer_previewer {
        title = 'Task',
        get_buffer_by_name = function(_, entry)
            return entry.value:id()
        end,
        define_preview = function(self, entry, status)
            if self.state.bufname ~= entry.value:id() then
                -- Cheap way to get decent display as Lua table
                local s = vim.inspect(entry.value.config)
                vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'lua')
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, utils.split_lines(s))
            end
        end
    }
end

local function terminal_previewer(opts)
    return previewers.new_buffer_previewer {
        title = 'Session Preview',
        get_buffer_by_name = function(_, entry)
            return entry.value:id()
        end,
        define_preview = function(self, entry, status)
            -- Preview by copying all lines from the terminal buffer Cache by buffer,
            -- but because terminal buffers may get new output we want to reset the
            -- content with some interval. This will however not update until new entry
            -- is selected in telescope, so it is far from ideal. It also won't get
            -- all the terminal highlighting.
            local delay_ms = 100

            local id = entry.value:id()
            local is_cached = self.state.bufname ~= id
            self.state.update_times = self.state.update_times or {}
            local last_time = self.state.update_times[id]

            if is_cached or (last_time and vim.loop.now() > last_time + delay_ms) then
                local buf = vim.F.npcall(function()
                   return entry.value.term.bufnr
                end)

                local lines = {'<ERROR: buffer not available>'}
                if buf and vim.api.nvim_buf_is_valid(buf) then
                    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                end

                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
                self.state.update_times[id] = vim.loop.now()
            end
        end,
    }
end

-- Actions

local function get_all(buf)
    local tasks = {}
    local picker = action_state.get_current_picker(buf)
    for entry in picker.manager:iter() do
        table.insert(tasks, entry.value)
    end
    return tasks
end

local function get_selected(buf)
    local tasks = {}
    local picker = action_state.get_current_picker(buf)
    for _, entry in ipairs(picker:get_multi_selection()) do
        table.insert(tasks, entry.value)
    end
    return tasks
end

local function get_current(buf)
    return { action_state.get_selected_entry().value }
end

local function task_action(getter, handler, post)
    return function(buf)
        local tasks = getter(buf)
        if #tasks == 0 then
            utils.warn('Nothing currently selected')
            return
        end

        actions.close(buf)

        for _, task in ipairs(tasks) do
            handler(task)
        end
        if post then
            post(tasks)
        end
    end
end

-- Pickers

function M.spawn(opts)
    opts = opts or {}

    -- Make sure to later use the window from which the picker was started
    opts.win = opts.win or vim.api.nvim_get_current_win()

    local c = config.telescope.spawn
    local open_single = vim.F.if_nil(opts.open_single, c.open_single)
    local show_running = vim.F.if_nil(opts.show_running, c.show_running)

    local tasks = discovery.tasks(opts)
    if not show_running then
        tasks = vim.tbl_filter(function(task)
            return not task:is_running()
        end, tasks)
    end

    pickers.new(opts, {
        prompt_title = "Spawn tasks",
        finder = finders.new_table {
            results = tasks,
            entry_maker = make_task_entry,
        },
        sorter = conf.generic_sorter(opts),
        previewer = task_previewer(opts),
        attach_mappings = function(buf, map)
            local act = function(opts)
                opts = opts or {}
                return function(task)
                    task:spawn(opts.win)
                    if opts.dir then
                        task.term:change_direction(opts.dir)
                    end
                    if opts.open then
                        task.term:open()
                    end
                end
            end
            local spawn_info = function(tasks)
                utils.info('Spawned %d tasks', #tasks)
            end

            local replace = {
                select_default = act { open = open_single },
                select_horizontal = act { open = open_single, dir = 'horizontal' },
                select_vertical = act { open = open_single, dir = 'vertical' },
                select_tab = act { open = open_single, dir = 'tab' },
            }
            for replaced, replacement in pairs(replace) do
                actions[replaced]:replace(task_action(get_current, replacement))
            end

            map('i', c.mappings.select_float, task_action(get_current, act()))
            map('n', c.mappings.select_float, task_action(get_current, act()))

            map('i', c.mappings.spawn_all, task_action(get_all, act(), spawn_info))
            map('n', c.mappings.spawn_all, task_action(get_all, act(), spawn_info))
            map('i', c.mappings.spawn_selected, task_action(get_selected, act(), spawn_info))
            map('n', c.mappings.spawn_selected, task_action(get_selected, act(), spawn_info))

            return true
        end,
    }):find()
end

function M.select(opts)
    opts = opts or {}
    pickers.new(opts, {
        prompt_title = "Select tasks",
        finder = finders.new_table {
            results = Task.get_all(),
            entry_maker = make_task_entry,
        },
        sorter = conf.generic_sorter(opts),
        previewer = terminal_previewer(opts),
        attach_mappings = function(buf, map)
            local attach = function(telescope_act, fn)
                actions[telescope_act]:replace(function()
                    local entry = action_state.get_selected_entry()
                    if not entry then
                        utils.warn('Nothing currently selected')
                        return
                    end
                    actions.close(buf)
                    fn(entry.value)
                end)
            end

            attach('select_default', function(task)
                task.term:open()
            end)

            return true
        end,
    }):find()
end

function M.edit(opts)
    opts = opts or {}
    pickers.new(opts, {
        prompt_title = "Edit config",
        finder = finders.new_table {
            results = discovery.config_files(opts),
            entry_maker = make_entry.gen_from_file(opts),
        },
        previewer = conf.file_previewer(opts),
        sorter = conf.file_sorter(opts),
    }):find()
end

return M
