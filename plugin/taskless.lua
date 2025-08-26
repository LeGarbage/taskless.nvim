vim.api.nvim_create_user_command("Taskless", function(opts)
    local taskless = require("taskless")
    local sub = opts.fargs[1]
    if sub == "build" then
        taskless.modules[vim.bo.filetype].build()
    elseif sub == "configure" then
        taskless.modules[vim.bo.filetype].configure()
    elseif sub == "run" then
        taskless.modules[vim.bo.filetype].run()
    elseif sub == "preset" then
        taskless.select_preset(opts.fargs[2])
    elseif sub == "target" then
        taskless.select_target(opts.fargs[2])
    elseif sub == "debug" then
        taskless.modules[vim.bo.filetype].debug()
    else
        print("Unknown subcommand: " .. tostring(sub))
    end
end, {
    nargs = "+",
    complete = function(_, line, _)
        local taskless = require("taskless")
        local args = vim.split(line, "%s+")
        local sub_cmd = args[2]
        local sub_arg = args[3]

        if not sub_arg then
            return { "build", "configure", "run", "preset", "target", "debug" }
        elseif sub_cmd == "preset" then
            return vim.tbl_map(function(p)
                return p.name
            end, taskless.modules[vim.bo.filetype].get_build_presets())
        elseif sub_cmd == "target" then
            return vim.tbl_map(function(t)
                return t.name
            end, taskless.modules[vim.bo.filetype].get_run_targets())
        end
    end,
})

-- Only trigger on c/c++ files
vim.api.nvim_create_autocmd("Filetype", {
    pattern = { "c", "cpp" },
    callback = function()
        local taskless = require("taskless")
        -- To prevent interferance with session managers like persistance, delay loading
        vim.defer_fn(taskless.load_state, 100)
    end,
    group = vim.api.nvim_create_augroup("Taskless", {}),
})
