local taskless = require("taskless")

vim.api.nvim_create_user_command("Taskless", function(opts)
    local sub = opts.fargs[1]
    if sub == "build" then
        taskless.build()
    elseif sub == "configure" then
        taskless.configure()
    elseif sub == "run" then
        taskless.run()
    elseif sub == "preset" then
        taskless.select_preset(opts.fargs[2])
    elseif sub == "target" then
        taskless.select_target(opts.fargs[2])
    else
        print("Unknown subcommand: " .. tostring(sub))
    end
end, {
    nargs = "+",
    complete = function(_, line, _)
        local args = vim.split(line, "%s+")
        local sub_cmd = args[2]
        local sub_arg = args[3]

        if not sub_arg then
            return { "build", "configure", "run", "preset", "target" }
        elseif sub_cmd == "preset" then
            return vim.tbl_map(function(p)
                return p.name
            end, taskless.get_build_presets())
        elseif sub_cmd == "target" then
            return vim.tbl_map(function(t)
                return t.name
            end, taskless.get_run_targets())
        end
    end,
})
