local M = {}

local telescope = require('telescope')
local action_state = require('telescope.actions.state')
local actions = require('telescope.actions')
local conf = require('telescope.config').values
local finders = require('telescope.finders')
local pickers = require('telescope.pickers')
local previewers = require('telescope.previewers')

local Task = require('toggletasks.task')
local discover = require('toggletasks.discovery').discover
local utils = require('toggletasks.utils')

local function task_previewer(opts)
    return previewers.new_buffer_previewer {
        title = 'Task',
        get_buffer_by_name = function(_, entry)
            return entry.value.config.name
        end,
        define_preview = function(self, entry, status)
            if self.state.bufname ~= entry.value.config.name then
                -- Cheap way to get decent display as Lua table
                local s = vim.inspect(entry.value.config)
                vim.api.nvim_buf_set_option(self.state.bufnr, 'filetype', 'lua')
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, utils.split_lines(s))
            end
        end
    }
end

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

local function spawn(opts)
    opts = opts or {}
    pickers.new(opts, {
        prompt_title = "Tasks",
        finder = finders.new_table {
            results = discover(opts.win, opts),
            entry_maker = make_task_entry,
        },
        sorter = conf.generic_sorter(opts),
        previewer = task_previewer(opts),
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
                task:spawn(opts.win)
            end)

            return true
        end,
    }):find()
end

local function select(opts)
    opts = opts or {}
    pickers.new(opts, {
        prompt_title = "Tasks",
        finder = finders.new_table {
            results = vim.tbl_values(Task.get_all()),
            entry_maker = make_task_entry,
        },
        sorter = conf.generic_sorter(opts),
        -- previewer = conf.grep_previewer(opts),
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

return telescope.register_extension {
    exports = {
        spawn = spawn,
        select = select,
        -- edit = edit,
    },
}
