# Taskless
## Worry less about your tasks

> [!NOTE]
> This plugin is based on [neovim tasks](https://github.com/Shatur/neovim-tasks)

> [!CAUTION]
> TODO: Add configuration options

## Installation

### Lazy
```
{
    "LeGarbage/taskless.nvim",
    dependencies = {
        "akinsho/toggleterm.nvim"
    }
    -- More configuration to come
}
```

## How to use

> [!NOTE]
> Make sure that neovim is in the root directory of your project

- Before using taskless, you must set up your cmake project first:
  - Set up your CMakeLists.txt like normal
  - Have a CMakePresets.json file in your root directory that looks something like this:
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
- The first time you use Taskless, run ```Taskless configure``` to generate the cmake api files
- Run ```Taskless build``` to build the project based on your selected preset
- Run ```Taskless run``` to build the project based on your selected preset and run the selected target
