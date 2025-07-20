local M = {}

local state = {
    current_preset = {},
    current_target = {},
}

local config

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
    -- Options for the terminal window
    --- @type vim.api.keyset.win_config
    win_config = {
        split = "below",
        win = -1,
        height = 10,
        style = "minimal",
    }
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
            -- To prevent interferance with session managers like persistance, delay loading
            vim.defer_fn(load_state, 100)
        end,
        group = vim.api.nvim_create_augroup("Taskless", {}),
    })
end

-- *** WINDOW UTILS ***
M.bufnr = -1
M.winnr = -1
M.job_id = -1
local function open_win(opts)
    opts = opts or config.win_config

    if not vim.api.nvim_buf_is_valid(M.bufnr) then
        M.bufnr = vim.api.nvim_create_buf(true, true)
    end

    if not vim.api.nvim_win_is_valid(M.winnr) then
        M.winnr = vim.api.nvim_open_win(M.bufnr, true, opts)
    else
        vim.api.nvim_set_current_win(M.winnr)
    end
end

---@param text string|string[]
local function win_write(text)
    if not vim.api.nvim_buf_is_valid(M.bufnr) then
        return
    end
    if type(text) == "string" then
        text = vim.split(text, "\n")
    end

    for i = #text, 1, -1 do
        if text[i] == "" then
            table.remove(text, i)
        else
            break
        end
    end

    local start_line = -1
    if vim.api.nvim_buf_get_lines(M.bufnr, 0, 1, false)[1] == "" then
        start_line = -2
    end
    vim.api.nvim_buf_set_lines(M.bufnr, start_line, -1, false, text)

    local last_line = vim.api.nvim_buf_line_count(M.bufnr)
    vim.api.nvim_win_set_cursor(M.winnr, { last_line, 0 })
end

-- *** GENERAL UTILS ***

--- @param command string[]
--- @param on_exit? fun(result: vim.SystemCompleted)
local function run_in_term(command, on_exit)
    open_win()

    local function handle_text(_, data)
        if data then
            vim.schedule(
                function()
                    win_write(data)
                end
            )
        end
    end

    vim.system(command, { text = true, stdin = true, stdout = handle_text, stderr = handle_text }, function(result)
        if on_exit then
            on_exit(result)
        end
    end)
end

---@param command string|string[]
local function start_term(command)
    open_win()
    local job_bufnr = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_set_current_buf(job_bufnr)

    M.job_id = vim.fn.jobstart(command, {
        term = true,
        on_exit = function()
            local termlines = vim.api.nvim_buf_get_lines(job_bufnr, 0, -1, false)

            open_win()
            vim.api.nvim_set_current_buf(M.bufnr)

            win_write(termlines)
        end
    })
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
        M.build(vim.schedule_wrap(function(result)
            if result.code ~= 0 then
                vim.notify("Could not run target: Build failed", vim.log.levels.ERROR, { title = "Taskless" })
                return
            end

            local build_path = string.gsub(state.current_preset.configurePreset.binaryDir,
                [[${sourceDir}/]], "")
            start_term(string.format("./%s", build_path .. "/" .. state.current_target.artifacts[1].path))
        end))
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
