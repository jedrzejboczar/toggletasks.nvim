# toggletasks.nvim

Neovim project-local task management: JSON + [toggleterm.nvim](https://github.com/akinsho/toggleterm.nvim) + [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim/).

## Features

* Define task via JSON, similarly to [VS Code Tasks](https://code.visualstudio.com/Docs/editor/tasks)
* Collect JSON configs from multiple directories: global/tab/win CWD, LSP root dir
* Run tasks in terminals managed by [toggleterm](https://github.com/akinsho/toggleterm.nvim)
* Use [telescope](https://github.com/nvim-telescope/telescope.nvim/) to spawn single/multiple tasks
* Filter tasks based on #tags defined in config files
* Use [telescope](https://github.com/nvim-telescope/telescope.nvim/) to view/open/kill tasks

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
}
```

## Configuration

Run `require('toggletasks').setup { ... }` in your `init.lua` to configure this plugin.
Available options (with default values):

```lua
require('toggletasks').setup {
    debug = false,
    short_paths = true,  -- display relative paths when possible
    -- Paths to task configuration files (relative to scanned directory)
    search_paths = {
        'toggletasks.json',
        '.toggletasks.json',
        '.nvim/toggletasks.json',
    },
    -- Directories to consider when searching for available tasks for current window
    scan = {
        global_cwd = true,  -- vim.fn.getcwd(-1, -1)
        tab_cwd = true,     -- vim.fn.getcwd(-1, tab)
        win_cwd = true,     -- vim.fn.getcwd(win)
        lsp_root = true,    -- root_dir for first LSP available for the buffer
        dirs = {},          -- explicit list of directories to search
    },
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
            },
        },
    },
}
```

To load telescope pickers:

```lua
require('telescope').load_extension('toggletasks')
```

## JSON config format

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

Variable expansion is supported using the syntax `${VAR}`.
Environmental variables will be expanded in fields: `cwd`, `env`.
Additionally some special variables will be expanded in fields: `cmd`, `cwd`, `env`.
Available special variables (snake case to minimize collisions with env):

* `${config_dir}` - location of the config file from which the task has been loaded
* `${lsp_root}` - root_dir of a language server with highest priority for current buffer
* `${win_cwd}` - Vim's window-local CWD
* `${tab_cwd}` - Vim's tab-local CWD
* `${global_cwd}` - Vim's global CWD
* `${file}` - absolute path to the current buffer's file
* `${file_ext}` - current file's extension
* `${file_tail}` - current file's tail (`fnamemodify(..., ':p:t')`)
* `${file_head}` - current file's head (`fnamemodify(..., ':p:h')`)

Example configuration file `.toggletasks.json`:

```json
{
    "tasks": {
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
    }
}
```

## Usage

To use this plugin use the included telescope pickers:

* spawn tasks: `Telescope toggletasks spawn`
* select running tasks (open/kill): `Telescope toggletasks select`
* edit config files: `Telescope toggletasks edit`

These commands can be mapped to keybindings, e.g.

```lua
vim.keymap.set('n', '<space>ts', require('telescope').extensions.toggletasks.spawn, { desc = 'toggletasks: spawn' })
```
When selecting tasks to be spawned, one can just type `#tagname` in the prompt to filter based on
tag. This is currently using the default string based matching but should work correctly in most cases.
To select all tasks that are currently visible press `<C-a>` (default). To manually pick tasks use
`<Tab>`/`<S-Tab>` (telescope defaults) to perform multi-selection and press `<C-a>` to spawn
selected tasks.

## TODO

- [ ] Integration with [possession.nvim](https://github.com/jedrzejboczar/possession.nvim) by marking
    tasks with `possession` tag - no changes required in this plugin
- [ ] Option to define some tasks from Lua in setup
- [ ] Task "templates": one task could inherit options from another ("extends")
