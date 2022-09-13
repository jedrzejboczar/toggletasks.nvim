[![Lint](https://github.com/jedrzejboczar/toggletasks.nvim/actions/workflows/lint.yml/badge.svg)](https://github.com/jedrzejboczar/toggletasks.nvim/actions/workflows/lint.yml)

# toggletasks.nvim

Neovim task runner: JSON/YAML + [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) + [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim/).

## Features

* Define task via JSON, similarly to [VS Code Tasks](https://code.visualstudio.com/Docs/editor/tasks)
* Support for **YAML**-based configuration using [lyaml](https://github.com/gvvaughan/lyaml)
* Collect configs from multiple directories: global/tab/win CWD, LSP root dir
* Run tasks in terminals managed by [toggleterm](https://github.com/akinsho/toggleterm.nvim)
* Use [telescope](https://github.com/nvim-telescope/telescope.nvim/) to spawn single/multiple tasks
* Filter tasks based on #tags defined in config files
* Use [telescope](https://github.com/nvim-telescope/telescope.nvim/) to view/open/kill tasks
* Automatic spawning on e.g. `SessionLoadPost` (see [Automatic task spawning](#automatic-task-spawning))

![usage video example](https://media.giphy.com/media/JrTEO0q8lkLVNLrehQ/giphy.gif)

## Overview

The main idea behind this plugin is to be able to easily define build/setup commands for different
projects, independently of your global editor configuration and to easily manage multiple background
tasks.

This task management plugin is heavily inspired by plugins such as
[yabs.nvim](https://github.com/pianocomposer321/yabs.nvim) and
[projectlaunch.nvim](https://github.com/sheodox/projectlaunch.nvim), as well as by
[VS Code Tasks](https://code.visualstudio.com/Docs/editor/tasks).
In fact, initially I planned to just extend [projectlaunch.nvim](https://github.com/sheodox/projectlaunch.nvim)
but after some work I decided that it would require to much changes and it will be easier to write
a separate plugin.

The main difference between [toggletasks.nvim](https://github.com/jedrzejboczar/toggletasks.nvim)
and other plugins is that toggletasks strictly integrates with existing solutions instead of writing
things from scratch, i.e.

* no terminal management from scratch - integrate with [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim)
* no selection UI from scratch - integrate with [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim/)

Other differences:

* `yabs.nvim` (currently, see [blog post](https://pianocomposer321.github.io/2022/05/03/why-im-rewriting-yabs.html))
  sources arbitrary Lua files; toggletasks uses only JSON which is much safer, though less powerfull
* `yabs.nvim` has the concept of different outputs/runners; toggletasks always uses toggleterm.nvim
* `projectlaunch.nvim` has a dedicated UI for managing tasks and running groups of tasks; toggletasks uses
  telescope to achieve similar results, allowing for multi-selection when spawning/selecting tasks
* `projectlaunch.nvim` has builtin runners for things like package.json/Makefile; this is not supported,
  but maybe something to consider in the future

## Installation

Example using [packer.nvim](https://github.com/wbthomason/packer.nvim):

```lua
use {
    'jedrzejboczar/toggletasks.nvim',
    requires = {
        'nvim-lua/plenary.nvim',
        'akinsho/toggleterm.nvim',
        'nvim-telescope/telescope.nvim/',
    },
    -- To enable YAML config support
    rocks = 'lyaml',
}
```

## Configuration

Run `require('toggletasks').setup { ... }` in your `init.lua` to configure this plugin.
Available options (with default values):

```lua
require('toggletasks').setup {
    debug = false,
    silent = false,  -- don't show "info" messages
    short_paths = true,  -- display relative paths when possible
    -- Paths (without extension) to task configuration files (relative to scanned directory)
    -- All supported extensions will be tested, e.g. '.toggletasks.json', '.toggletasks.yaml'
    search_paths = {
        'toggletasks',
        '.toggletasks',
        '.nvim/toggletasks',
    },
    -- Directories to consider when searching for available tasks for current window
    scan = {
        global_cwd = true,    -- vim.fn.getcwd(-1, -1)
        tab_cwd = true,       -- vim.fn.getcwd(-1, tab)
        win_cwd = true,       -- vim.fn.getcwd(win)
        lsp_root = true,      -- root_dir for first LSP available for the buffer
        dirs = {},            -- explicit list of directories to search or function(win): dirs
        rtp = false,          -- scan directories in &runtimepath
        rtp_ftplugin = false, -- scan in &rtp by filetype, e.g. ftplugin/c/toggletasks.json
    },
    tasks = {}, -- list of global tasks or function(win): tasks
                -- this is basically the "Config format" defined using Lua tables
    -- Language server priorities when selecting lsp_root (default is 0)
    lsp_priorities = {
        ['null-ls'] = -10,
    },
    -- Default values for task configuration options (available options described later)
    defaults = {
        close_on_exit = false,
        hidden = true,
    },
    -- Configuration of telescope pickers
    telescope = {
        spawn = {
            open_single = true,  -- auto-open terminal window when spawning a single task
            show_running = false, -- include already running tasks in picker candidates
            -- Replaces default select_* actions to spawn task (and change toggleterm
            -- direction for select horiz/vert/tab)
            mappings = {
                select_float = '<C-f>',
                spawn_smart = '<C-a>',  -- all if no entries selected, else use multi-select
                spawn_all = '<M-a>',    -- all visible entries
                spawn_selected = nil,   -- entries selected via multi-select (default <tab>)
            },
        },
        -- Replaces default select_* actions to open task terminal (and change toggleterm
        -- direction for select horiz/vert/tab)
        select = {
            mappings = {
                select_float = '<C-f>',
                open_smart = '<C-a>',
                open_all = '<M-a>',
                open_selected = nil,
                kill_smart = '<C-q>',
                kill_all = '<M-q>',
                kill_selected = nil,
                respawn_smart = '<C-s>',
                respawn_all = '<M-s>',
                respawn_selected = nil,
            },
        },
    },
}
```

To load telescope pickers:

```lua
require('telescope').load_extension('toggletasks')
```

## Config format

JSON configuration files are supported out-of-the-box via `vim.json` module.
To enable YAML support, [lyaml](https://github.com/gvvaughan/lyaml) must be installed.
It is possible to [use packer to install luarocks](https://github.com/wbthomason/packer.nvim#luarocks-support=),
see [Installation](#installation).

Available fields:

| Field | Type | Description |
| ----- | ---- | ----------- |
| name | `string` | descriptive name for the task; pair (name, config_file) is used to uniquely identify a task (to kill existing if re-running or to filter out already running tasks in picker) |
| id | `string?` | Optional ID to use instead of the default pair (name, config_file) |
| cmd | `string` | Command to run |
| cwd | `string?` | Task working directory |
| tags | `table<string>?` | Tags used to group and filter tasks |
| env | `table<string, string>?` | Additional environmental variables passed to task |
| clear_env | `boolean?` | If set to true, only environmental variables from `env` will be passed to task |
| close_on_exit | `boolean?` | Auto-close terminal when task job exists ([see toggleterm](https://github.com/akinsho/toggleterm.nvim#custom-terminals)) |
| hidden | `boolean?` | Don't include this task in toggleterm tasks list ([see toggleterm](https://github.com/akinsho/toggleterm.nvim#custom-terminals)) |
| count | `number?` | Use given terminal number ([see toggleterm](https://github.com/akinsho/toggleterm.nvim#custom-terminals)) |

Variable expansion is supported using the syntax `${VAR}` (escaped by double `$`, e.g. `$${VAR}` will expand to `${VAR}`).


Environmental variables will be expanded in fields: `cwd`, `env`.
Additionally some special variables will be expanded in fields: `cmd`, `cwd`, `env`.
Available special variables (snake case to minimize collisions with env):

* `${config_dir}` - location of the config file from which the task has been loaded
* `${lsp_root}` - root_dir of a language server with highest priority for current buffer
* `${win_cwd}` - Vim's window-local CWD
* `${tab_cwd}` - Vim's tab-local CWD
* `${global_cwd}` - Vim's global CWD
* `${file}` - absolute path to the current buffer's file

Vim [filename-modifiers](https://neovim.io/doc/user/cmdline.html#filename-modifiers) can be used inside the expansion
to modify the paths (by default all paths are absoulte),
e.g. `${file:t:r}` will transform `/path/to/my-file.txt` into `my-file`.

JSON configuration example file:

```json
{
    "tasks": [
        {
            "name": "Echo example",
            "cmd": "echo 'Current file = ${file}'"
        },
        {
            "name": "System logs",
            "cmd": "journalctl -b --follow",
            "tags": ["dev"]
        },
        {
            "name": "Makefile build",
            "cmd": "make -j",
            "cwd": "${config_dir}",
            "tags": ["build", "make"]
        },
        {
            "name": "CMake setup",
            "cmd": "mkdir -p build && cd build && cmake ..",
            "cwd": "${config_dir}",
            "tags": ["cmake"]
        },
        {
            "name": "CMake build",
            "cmd": "cmake --build build -j",
            "cwd": "${config_dir}",
            "tags": ["build", "cmake"]
        },
        {
            "name": "django runserver",
            "cmd": "python manage.py runserver",
            "cwd": "${config_dir}",
            "env": {
                "PATH": "${config_dir}/venv/bin:${PATH}"
            },
            "tags": ["dev"]
        },
        {
            "name": "frontend",
            "cmd": "npm run serve",
            "cwd": "${config_dir}/frontend",
            "tags": ["dev"]
        }
    ]
}
```

YAML configuration example:

```yaml
tasks:
- name: Echo example
  cmd: echo 'Current file = ${file}'
- name: django runserver
  cmd: python manage.py runserver
  cwd: ${config_dir}
  env:
    PATH: ${config_dir}/venv/bin:${PATH}
  tags:
  - dev
```

## Usage

To use this plugin use the included telescope pickers:

* spawn tasks: `Telescope toggletasks spawn`
* select running tasks (open/kill/respawn): `Telescope toggletasks select`
* edit config files: `Telescope toggletasks edit`

These commands can be mapped to keybindings, e.g.

```lua
vim.keymap.set('n', '<space>ts', require('telescope').extensions.toggletasks.spawn,
    { desc = 'toggletasks: spawn' })
```
When selecting tasks to be spawned, one can just type `#tagname` in the prompt to filter based on
tag. This is currently using the default string based matching but should work correctly in most cases.
To select all tasks that are currently visible press `<C-a>` (default). To manually pick tasks use
`<Tab>`/`<S-Tab>` (telescope defaults) to perform multi-selection and press `<C-a>` to spawn
selected tasks.

### Commands

The following commands are available:

* `ToggleTasksInfo` - show current configuration
* `ToggleTasksConvert <from_file> <to_file>` - convert between configuration file formats (by file extension)

### Automatic task spawning

It is possible to automatically launch tasks on autocmd events, e.g. to launch tasks on `VimEnter`
or `SessionLoadPost`. This plugin exposes convenient function to achieve that.

For example, to launch all tasks marked with the `auto` tag whenever a session is loaded use:

```lua
require('toggletasks').auto_spawn('SessionLoadPost', 'auto')
```

The first argument (`event`) is the same as for `vim.api.nvim_create_autocmd`.
For more fine grained `auto_spawn` can take a function as the second argument:

```lua
require('toggletasks').auto_spawn({'VimEnter', 'SessionLoadPost'}, function(tasks)
    return tasks
        :with_tag('auto')
        :not_tag('test')
        :from_file('/some/path/toggletasks.json')
        :name_matches('^/some/path.*$')
        :filter(function(task)
            return task.config.name ~= 'Hello world'
        end)
end)
```
## Global tasks

Sometimes it would be handy to share some common tasks between projects without the need to add config files
to all of these. It might also be handy to only include some tasks for certain filetypes.
There are several ways to achieve this in `toggletasks.nvim`.

1. Put task config file somewhere under `&runtimepath` (e.g. `~/.config/nvim/toggletasks.json`) and enable
   option `scan.rtp = true`. Note that this adds a lot of paths for scanning so in theory it might have
   some performance impact (but probably not noticeable).

2. Put task config files for given filetypes under `ftplugin/FILETYPE` in `&runtimepath` and enable
   the option `scan.rtp_ftplugin = true` (should be much faster than 1.). For example, to add Lua-specific
   tasks one could add a file `~/.config/nvim/ftplugin/lua/toggletasks.json`.

3. Use the setup option `scan.dirs` as a `function(win)`, and return the directories in which to search for task
   config files. You can use the `win` argument to get the filetype of current buffer, or to check any other
   conditions, which can be used to select specific directories with task config files.

4. Define tasks directly in Lua in your setup function. Use a function to have even more control over which
   tasks should be included, e.g.

```lua
require('toggletasks').setup {
    tasks = function(win)
        local ft = vim.api.nvim_buf_get_option(vim.api.nvim_win_get_buf(win), 'filetype')
        local tasks = {
            {
                name = 'Some task',
                cmd = 'echo "hello"'
            },
        }
        if ft == 'lua' then
            -- table.insert(tasks, { name = ... })
        end
        return tasks
    end,
    -- ...
}
```

## TODO

- [ ] Integration with [possession.nvim](https://github.com/jedrzejboczar/possession.nvim) by marking
    tasks with `possession` tag - no changes required in this plugin
- [ ] Task "templates": one task could inherit options from another ("extends")
