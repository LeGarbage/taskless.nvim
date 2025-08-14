# Taskless
## Worry less about your tasks

> [!NOTE]
> This plugin is based on [neovim tasks](https://github.com/Shatur/neovim-tasks)

## Installation

### Lazy
```
{
    "LeGarbage/taskless.nvim",
    -- dependencies = { "mfussenegger/nvim-dap" } -- Only if you are using dap
    opts = {
        -- See configuration below
    }
}
```

## Configuration

Default configuration:
```
---@class Config
---@field default_preset string The default preset that will be used if none is provided. Set to empty string to disable
---@field use_only_target boolean Whether to use the only target if no target is selected and there is only one
---@field close_window boolean Whether to close the window after a successful build/config
---@field win_config vim.api.keyset.win_config Options for the terminal window

---@type Config
local defaults = {
    default_preset = "debug",
    use_only_target = true,
    close_window = false,
    win_config = {
        split = "below",
        win = -1,
        height = 10,
        style = "minimal",
    }
}
```

## How to use

> [!IMPORTANT]
> Make sure that neovim is in your project's root directory

- Before using taskless, you must set up your cmake project first:
  - Set up your CMakeLists.txt like normal
  - Have a CMakePresets.json file in your project's root directory that looks something like this:
```
{
    "version": 8,
    "configurePresets": [
        {
            "name": "debug",
            "displayName": "Config Debug",
            "binaryDir": "${sourceDir}/build/debug",
        }
    ],
    "buildPresets": [
        {
            "name": "debug",
            "displayName": "Build Debug",
            "configurePreset": "debug"
        }
    ]
}
```
- You can set your build preset using the ```Taskless preset``` command. If you know what preset you want, you can use ```Taskless preset <preset name>``` to select that preset. When run without a preset specified. A menu will pop up asking you to choose one, or the onl preset will be chosen if you have one.
- The configure preset is determined based on your build preset
- You can set your run target using the ```Taskless target``` command. If you know what target you want, you can use ```Taskless target <target name>``` to select that target. When run without a target specified. A menu will pop up asking you to choose one, or the onl target will be chosen if you have one.
> [!TIP]
>  The first time you use Taskless, run ```Taskless configure``` to generate the cmake api files
- Run ```Taskless build``` to build the project based on your selected preset
- Run ```Taskless run``` to build the project based on your selected preset and run the selected target
- Run ```Taskless debug``` to build the project based on your selected preset start the debugger
