local Path = require('plenary.path')
local config = require('toggletasks.config')
local loader = require('toggletasks.loader')
local discovery = require('toggletasks.discovery')
local utils = require('toggletasks.utils')

local function plugin_info()
    local info = {
        ['lyaml installed'] = pcall(require, 'lyaml'),
        ['Supported extensions'] = table.concat(loader.supported_extensions(), ', '),
        ['Config'] = vim.inspect(vim.tbl_extend('force', {}, config)),
    }
    local lines = {}
    for key, val in pairs(info) do
        table.insert(lines, key .. ':')
        for _, line in ipairs(vim.split(tostring(val), '\n', { plain = true })) do
            table.insert(lines, '  ' .. line)
        end
    end
    return table.concat(lines, '\n')
end

local function cmd(name, opts, fn)
    vim.api.nvim_create_user_command(name, fn, opts)
end

local function add_commands()
    cmd('ToggleTasksInfo', {
        desc = 'Show plugin information',
    }, function(opts)
        print(plugin_info())
    end)

    cmd('ToggleTasksConvert', {
        nargs = '+',
        complete = 'file',
        bang = true,
        desc = 'Convert between configuration file formats',
    }, function(opts)
        if #opts.fargs ~= 2 then
            utils.error('Usage: ToggleTasksConvert <from_file> <to_file>')
            return
        end
        if Path:new(opts.fargs[2]):exists() and not opts.bang then
            utils.error('File exists. Use "ToggleTasksConvert!" to overwrite')
            return
        end
        loader.convert(opts.fargs[1], opts.fargs[2])
        utils.info('Saved file: "%s"', opts.fargs[2])
    end)
end

local function setup(opts)
    config.setup(opts)
    add_commands()
end

local augroup = utils.lazy(function()
    return vim.api.nvim_create_augroup('ToggleTasks', { clear = true })
end)

-- Setup autocmd to spawn all tasks matching a tag on given event.
--@param event string|table: see nvim_create_autocmd
--@param tag_or_filter string|function: use tasks containing given tag,
-- if this is a function than it should map fn(TaskQuery) -> TaskQuery
local function auto_spawn(event, tag_or_filter)
    local is_fn = type(tag_or_filter) == 'function'
    local filter = is_fn and tag_or_filter or function(tasks)
        return tasks:with_tag(tag_or_filter)
    end

    local callback = function()
        local tasks = filter(discovery.tasks())
        if #tasks ~= 0 then
            for _, task in ipairs(tasks) do
                -- It seems that spawnning during SessionLoadPost will not setup the buffer
                -- correctly (no TermOpen?). Scheduling for next loop step solves the issue.
                vim.schedule(function()
                    task:spawn()
                end)
            end
            utils.info('Spawned %d tasks', #tasks)
        end
    end

    vim.api.nvim_create_autocmd(event, {
        group = augroup(),
        desc = 'Auto spawn tasks with #' .. tostring(tag_or_filter),
        -- FIXME: for some reason e.g. SessionLoadPost triggers multiple times,
        -- so we restrict how often this can be called
        callback = utils.throttle(callback, 1000),
    })
end

return {
    setup = setup,
    auto_spawn = auto_spawn,
}
