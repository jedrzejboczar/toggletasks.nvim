local Path = require('plenary.path')
local config = require('toggletasks.config')
local loader = require('toggletasks.loader')
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

return {
    setup = setup,
}
