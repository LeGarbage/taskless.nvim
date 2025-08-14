local M = {}

local state = {
    current_preset = {},
    current_target = {},
}

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

---@type Config
local config

-- *** STATE UTILS ***

-- Save the state to disk
local function save_state()
    vim.fn.writefile({ vim.json.encode(state) }, "taskless.json")
end

-- Load the configured state
function M.load_state()
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

-- Load the user's config and use defaults for non-specified options
function M.setup(user_config)
    if user_config then
        config = vim.tbl_deep_extend("force", defaults, user_config)
    else
        config = defaults
    end
end

-- *** WINDOW UTILS ***
M.bufnr = -1
M.winnr = -1
M.job_id = -1

-- Opens the output window
---@param opts? vim.api.keyset.win_config The window options to use for the new window
local function open_win(opts)
    -- Use the configuration if none is provided
    opts = opts or config.win_config

    -- Create a buffer if none exists
    if not vim.api.nvim_buf_is_valid(M.bufnr) then
        -- A scratch buffer
        M.bufnr = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_set_option_value("readonly", true, { buf = M.bufnr })
    end

    -- Create a new window if it doesn't exist and focus it
    if not vim.api.nvim_win_is_valid(M.winnr) then
        M.winnr = vim.api.nvim_open_win(M.bufnr, true, opts)
    else
        vim.api.nvim_set_current_win(M.winnr)
    end
end


-- Close the output window
local function close_win()
    vim.api.nvim_win_close(M.winnr, true)
end

-- Write text to the output window
---@param text string|string[] The text or list of lines to display
---@param newline? boolean Whether to add a blank line after the output
local function win_write(text, newline)
    if not vim.api.nvim_buf_is_valid(M.bufnr) then
        return
    end

    -- Split the string by newline
    if type(text) == "string" then
        text = vim.split(text, "\n")
    end


    -- Remove blank lines
    for i = #text, 1, -1 do
        if text[i] == "" then
            table.remove(text, i)
        else
            break
        end
    end

    -- Insert the blank line at the end
    if newline then
        table.insert(text, "")
    end

    -- Start at the bottom, or ovewrite the top line if we are the first to print
    local start_line = -1
    if vim.api.nvim_buf_get_lines(M.bufnr, 0, 1, false)[1] == "" then
        start_line = -2
    end

    -- Write the text
    vim.api.nvim_set_option_value("readonly", false, { buf = M.bufnr })
    vim.api.nvim_buf_set_lines(M.bufnr, start_line, -1, false, text)
    vim.api.nvim_set_option_value("readonly", true, { buf = M.bufnr })

    -- Set the cursor to the end of the text
    local last_line = vim.api.nvim_buf_line_count(M.bufnr)
    vim.api.nvim_win_set_cursor(M.winnr, { last_line, 0 })
end

-- *** GENERAL UTILS ***

-- Run a command and pipe the output to the output window
--- @param command string[]
--- @param on_exit? fun(result: vim.SystemCompleted)
local function run_in_term(command, on_exit)
    open_win()

    local function handle_text(_, data)
        if data then
            -- Prevent weird stuff from happening with async
            vim.schedule(
                function()
                    win_write(data)
                end
            )
        end
    end

    -- Run the command and handle the output
    vim.system(command, { text = true, stdin = true, stdout = handle_text, stderr = handle_text },
        vim.schedule_wrap(function(result)
            -- Add a newline after the output
            win_write("", true)
            if on_exit then
                on_exit(result)
            end
        end))
end

-- Run an interactive terminal that uses stdin
---@param command string|string[]
local function start_term(command)
    open_win()

    -- Create a new throwaway buffer to use as the terminal
    local job_bufnr = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(job_bufnr)

    M.job_id = vim.fn.jobstart(command, {
        term = true,
        on_exit = function()
            -- Save the state of the terminal
            local termlines = vim.api.nvim_buf_get_lines(job_bufnr, 0, -1, false)

            open_win()
            vim.api.nvim_set_current_buf(M.bufnr)
            -- Delete the old buffer
            vim.api.nvim_buf_delete(job_bufnr, { force = true })
            -- Write the output to the output window
            win_write(termlines, true)
        end
    })

    -- Start the terminal with input captured
    vim.api.nvim_command("startinsert")
end

-- *** CONFIGURE UTILS ***

function M.configure()
    if not next(state.current_preset) then
        vim.notify("Configure failed: Please select a preset", vim.log.levels.ERROR, { title = "Taskless" })
    elseif not (state.current_preset.configurePreset) then
        vim.notify("Configure failed: Build preset does not specify a configure preset", vim.log.levels.ERROR,
            { title = "Taskless" })
    else
        run_in_term({ "cmake", "--preset", state.current_preset.configurePreset.name }, function(result)
            if result.code == 0 then
                local api_dir = string.gsub(
                    state.current_preset.configurePreset.binaryDir .. "/.cmake/api/v1/query/", [[${sourceDir}/]], "")
                local api_file = api_dir .. "codemodel-v2"
                if vim.fn.filewritable(api_file) == 0 then
                    vim.fn.mkdir(api_dir, "p")
                    vim.fn.writefile({ "" }, api_file)
                end

                if config.close_window then
                    close_win()
                end
            end
        end)
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

---@param on_done? fun(result: vim.SystemCompleted)
function M.build(on_done)
    if not next(state.current_preset) then
        vim.notify("Build failed: Please select a preset", vim.log.levels.ERROR, { title = "Taskless" })
        return false
    end

    -- local command = string.format("cmake --build --preset %s", state.current_preset.name)
    local command = { "cmake", "--build", "--preset", state.current_preset.name }

    on_done = on_done or function(result)
        if result.code == 0 and config.close_window then
            close_win()
        end
    end

    run_in_term(command, on_done)
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
        return {}
    elseif not (state.current_preset.configurePreset) then
        vim.notify("Could not get targets: Build preset does not specify a configure preset", vim.log.levels.ERROR,
            { title = "Taskless" })
        return {}
    elseif not (state.current_preset.configurePreset.binaryDir) then
        vim.notify("Could not get targets: Configure preset does not specify a binary dir", vim.log.levels.ERROR,
            { title = "Taskless" })
        return {}
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
        M.build(function(result)
            if result.code ~= 0 then
                vim.notify("Could not run target: Build failed", vim.log.levels.ERROR, { title = "Taskless" })
                return
            end

            local build_path = string.gsub(state.current_preset.configurePreset.binaryDir,
                [[${sourceDir}/]], "")
            start_term(string.format("./%s", build_path .. "/" .. state.current_target.artifacts[1].path))
        end)
    end
end

function M.select_target(target)
    local targets = M.get_run_targets()
    if #targets == 0 then return end

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

-- *** DEBUG UTILS ***
function M.debug()
    if not next(state.current_target) then
        vim.notify("Could not debug target: Please select a target", vim.log.levels.ERROR, { title = "Taskless" })
    else
        M.build(function(result)
            if result.code ~= 0 then
                vim.notify("Could not debug target: Build failed", vim.log.levels.ERROR, { title = "Taskless" })
                return
            end

            local ok, dap = pcall(require, "dap")

            if not ok then
                vim.notify("Could not debug target: Dap not installed", vim.log.levels.ERROR, { title = "Taskless" })
                return
            end

            close_win()

            dap.continue()
        end)
    end
end

return M
