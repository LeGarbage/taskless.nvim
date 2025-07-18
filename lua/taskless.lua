local M = {}

local state = {
    current_preset = {},
    current_target = {},
}

local config

local Terminal = require("toggleterm.terminal").Terminal
local term = Terminal:new({ display_name = "CMake", close_on_exit = false, direction = "horizontal" })

-- *** STATE UTILS ***

local function save_state()
    vim.fn.writefile({ vim.json.encode(state) }, "taskless.json")
end

local function load_state()
    local ok, state_text = pcall(vim.fn.readfile, "taskless.json")

    if ok then
        state = vim.json.decode(table.concat(state_text))
    else
        vim.defer_fn(function()
            vim.notify("Could not load configuration", vim.log.levels.WARN, { title = "Taskless" })
            if #config.default_preset > 0 and not next(state.current_preset) then
                M.select_preset(config.default_preset, false)
            end

            local target_ok, targets = pcall(M.get_run_targets)
            targets = targets or {}
            local target = targets[1]

            if target and target_ok and config.use_only_target and not next(state.current_target) then
                state.current_target = target
                vim.schedule(function()
                    vim.notify("Target " .. state.current_target.name .. " has been selected", vim.log.levels.INFO,
                        { title = "Taskless" })
                end)
            end
        end, 100)
    end
end

-- *** SETUP ***
local defaults = {
    -- The default preset that will be used if none is provided
    -- Set to empty string to disable
    default_preset = "debug",
    -- Whether to use the only target if no target is selected and there is only one
    use_only_target = true,
}

function M.setup(user_config)
    if user_config then
        config = vim.tbl_deep_extend("force", defaults, user_config)
    else
        config = defaults
    end

    -- Only trigger on c/c++ files
    vim.api.nvim_create_autocmd("Filetype", {
        pattern = { "c", "cpp" },
        callback = function()
            -- HACK: To prevent interferance with session managers like persistance, delay loading

            vim.defer_fn(load_state, 100)
        end,
        group = vim.api.nvim_create_augroup("Taskless", {}),
    })
end

-- *** GENERAL UTILS ***
local function run_in_term(cmd)
    if not term:is_open() then
        term:toggle()
    end
    term:send(cmd, state.current_preset.name)
end

-- *** CONFIGURE UTILS ***

function M.configure()
    if not next(state.current_preset) then
        vim.notify("Configure failed: Please select a preset", vim.log.levels.ERROR, { title = "Taskless" })
    elseif not (state.current_preset.configurePreset) then
        vim.notify("Configure failed: Build preset does not specify a configure preset", vim.log.levels.ERROR,
            { title = "Taskless" })
    else
        run_in_term(string.format("cmake --preset %s", state.current_preset.configurePreset.name))
        local api_dir = string.gsub(
            state.current_preset.configurePreset.binaryDir .. "/.cmake/api/v1/query/", [[${sourceDir}/]], "")
        local api_file = api_dir .. "codemodel-v2"
        if vim.fn.filewritable(api_file) == 0 then
            vim.fn.mkdir(api_dir, "p")
            vim.fn.writefile({ "" }, api_file)
        end
    end
end

-- *** BUILD UTILS ***

function M.get_build_presets()
    local text = vim.fn.readfile(vim.fn.getcwd() .. "/" .. "CMakePresets.json")
    local presets = vim.json.decode(table.concat(text))
    for index, build_preset in ipairs(presets.buildPresets) do
        build_preset.configurePreset = presets.configurePresets[index]
    end
    return presets.buildPresets
end

function M.build()
    if not next(state.current_preset) then
        vim.notify("Build failed: Please select a preset", vim.log.levels.ERROR, { title = "Taskless" })
    else
        run_in_term(string.format("cmake --build --preset %s", state.current_preset.name))
    end
end

function M.select_preset(preset, save)
    if not vim.fn.filereadable(vim.fn.getcwd() .. "/" .. "CMakePresets.json") then
        vim.notify("CMakePresets.json not found", vim.log.levels.ERROR, { title = "Taskless" })
        return
    end
    local presets = M.get_build_presets()
    if preset then
        local found = false
        for _, preset_data in ipairs(presets) do
            if preset_data.name == preset then
                found = true
                state.current_preset = preset_data
                break
            end
        end

        if not found then
            vim.notify(preset .. " is not a valid preset", vim.log.levels.ERROR, { title = "Taskless" })
            return
        end
    elseif #presets == 1 then
        state.current_preset = presets[1]
    else
        vim.ui.select(presets, {
            prompt = "Select build preset",
            format_item = function(item)
                return item.name
            end
        }, function(choice, idx)
            if not idx then return end
            state.current_preset = choice
        end)
    end

    vim.notify("Preset " .. state.current_preset.name .. " has been selected", vim.log.levels.INFO,
        { title = "Taskless" })

    if type(save) == "nil" or save then
        save_state()
    end
end

-- *** RUN UTILS ***

function M.get_run_targets()
    if not next(state.current_preset) then
        vim.notify("Could not get targets: Please select a preset", vim.log.levels.ERROR, { title = "Taskless" })
        return
    elseif not (state.current_preset.configurePreset) then
        vim.notify("Could not get targets: Build preset does not specify a configure preset", vim.log.levels.ERROR,
            { title = "Taskless" })
        return
    elseif not (state.current_preset.configurePreset.binaryDir) then
        vim.notify("Could not get targets: Configure preset does not specify a binary dir", vim.log.levels.ERROR,
            { title = "Taskless" })
        return
    end

    local api_path = string.gsub(state.current_preset.configurePreset.binaryDir .. "/.cmake/api/v1/reply",
        [[${sourceDir}/]], "")
    local index_text = vim.fn.readfile(vim.fn.glob(api_path .. "/index*.json"))
    local index_data = vim.json.decode(table.concat(index_text))
    local codemodel_text = vim.fn.readfile(api_path .. "/" .. index_data.reply["codemodel-v2"].jsonFile)
    local codemodel_data = vim.json.decode(table.concat(codemodel_text))
    local targets = codemodel_data.configurations[1].targets
    local target_data = {}
    for _, target in ipairs(targets) do
        local target_text = vim.fn.readfile(api_path .. "/" .. target.jsonFile)
        table.insert(target_data, vim.json.decode(table.concat(target_text)))
    end
    return target_data
end

function M.run()
    if not next(state.current_target) then
        vim.notify("Could not run target: Please select a target", vim.log.levels.ERROR, { title = "Taskless" })
    else
        M.build()

        local build_path = string.gsub(state.current_preset.configurePreset.binaryDir,
            [[${sourceDir}/]], "")
        run_in_term(string.format("./%s", build_path .. "/" .. state.current_target.artifacts[1].path))
    end
end

function M.select_target(target)
    local targets = M.get_run_targets()
    if not targets then return end

    if target then
        local found = false
        for _, target_data in ipairs(targets) do
            if target_data.name == target then
                found = true
                state.current_target = target_data
                break
            end
        end

        if not found then
            vim.notify(target .. " is not a valid target", vim.log.levels.ERROR, { title = "Taskless" })
            return
        end
    elseif #targets == 1 then
        state.current_target = targets[1]
    else
        vim.ui.select(targets, {
            prompt = "Select target",
            format_item = function(item)
                return item.name
            end
        }, function(choice, idx)
            if not idx then return end
            state.current_target = choice
        end)
    end

    vim.notify("Target " .. state.current_target.name .. " has been selected", vim.log.levels.INFO,
        { title = "Taskless" })
    save_state()
end

return M
