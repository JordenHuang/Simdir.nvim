--TODO:
-- 1. cp command
-- 2. custom keymaps
-- 3. o key should open file in another window
-- 4. understanding why and when to add fnameescape
local M = {}

local core = require('simdir.core')
local ops = require('simdir.operations')


M.default_config = {}

M.commands = {
    "open_parent_dir",  -- Open current working directory
    "open_dir",  -- Open specified directory
}

M.info_table = {}

M.open_dir = function(path)
    local lines
    local cmd = string.format([[ls %s -alh]], vim.fn.fnameescape(path))
    local job_id = vim.fn.jobstart(
        cmd,
        {
            stdout_buffered = true,
            stderr_buffered = true,
            on_stdout = function(_, data, _)
                if not data then return
                else lines = data end
            end,
            on_stderr = function(_, data, _)
                for _, line in ipairs(data) do
                    if line ~= '' then
                        vim.schedule(function() vim.notify(line, vim.log.levels.ERROR) end)
                    end
                end
            end,
            on_exit = function(_, code, _) --[[ print("exit with code:", code) return --]] end
        }
    )
    -- Wait the job to exit before we continue, timeout is 2 seconds
    -- return if exit_code is not 0
    local exit_code = vim.fn.jobwait({job_id}, 2000)
    if exit_code[1] ~= 0 then return end

    core.buf_open({})
    -- Clear the buffer content
    core.buf:write_lines(0, -1, {})
    -- Write path message
    core.buf:write_lines(0, -1, {path .. ':'})
    -- Highlight the path text
    core.buf:set_hl(core.hl_ns_id, 'DiagnosticOk', 0, 0, #path)

    M.info_table = core.parse_lines(lines, path)
    -- print(vim.inspect(M.info_table))

    for i, line in ipairs(lines) do
        if line ~= '' then
            local data = M.info_table[i]
            local row = data.line_number - 1
            -- print(vim.inspect(data))
            -- print('linenr', linenr)
            -- print('line', line)
            core.buf:write_lines(-1, -1, {line})

            -- Apply highlights
            if data.ftype == 'd' then
                core.buf:set_hl(core.hl_ns_id, 'Simdir_hl_dirname', row, data.fname_hl_s, data.fname_hl_e)
            elseif data.ftype == 'l' then
                core.buf:set_hl(core.hl_ns_id, 'Simdir_hl_symlink', row, data.fname_hl_s, data.fname_hl_e)
                if data.misc.link_to_ftype == 'd' then
                    core.buf:set_hl(core.hl_ns_id, 'Simdir_hl_dirname', row, data.misc.link_hl_s, data.misc.link_hl_e)
                end
            end
        end
    end

    core.cursor_hijack()
end

M.open_parent_dir = function()
    M.open_dir(vim.uv.cwd())
end

M.open_path = function()
    local line_nr = vim.api.nvim_win_get_cursor(0)[1]
    if line_nr == 1 or line_nr == 2 then return end
    local data = M.info_table[line_nr - 1]

    if data.ftype == 'd' then
        local last_path = M.info_table[2].fpath
        M.open_dir(data.fpath)
        if data.fname == ".." then
            core.move_cursor_on_last_directory(last_path, M.info_table)
        end
    elseif data.ftype == 'l' then
        if data.misc.link_to_ftype == '-' then
            vim.cmd('edit ' .. data.fpath)
        elseif data.misc.link_to_ftype == "broken" then
            vim.notify("Link is broken", vim.log.levels.WARN)
        else
            local last_path = M.info_table[2].fpath
            M.open_dir(data.fpath)
            if data.fname == ".." then
                core.move_cursor_on_last_directory(last_path, M.info_table)
            end
        end
    else
        vim.cmd('edit ' .. data.fpath)
    end
end

M.reload_wrap = function(path)
-- print("before reload wrap")
    return vim.schedule_wrap(function()
        local prev_info_table = M.info_table
        M.open_dir(path)
        -- Copy marks
        local i = 1
        for j = 1, #prev_info_table do
            if M.info_table[i].fpath == prev_info_table[j].fpath then
                M.info_table[i].mark = prev_info_table[j].mark
                i = i + 1
            end
            if i > #M.info_table then break end
        end
        -- Set sign column
        for j, _ in ipairs(M.info_table) do
            ops.set_mark(core.buf, M.info_table, j+1, M.info_table[j].mark)
        end
-- print("inside and after reload wrap")
    end)
end

M.keys = function(key)
    if vim.api.nvim_get_current_win() ~= core.win_id then return end

    local path = M.info_table[2].fpath

    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line_nr = cursor_pos[1]
    if line_nr == 1 or line_nr == 2 then return end
    local data = M.info_table[line_nr - 1]

    local reload_wrap = M.reload_wrap(path)
    -- open file or directory
    if key == 'o' or key == "CR" then
        M.open_path()

        -- touch command, for creating empty file
    elseif key == 'T' then
        ops.touch(path, reload_wrap)

        -- mkdir command
    elseif key == '+' then
        ops.mkdir(path, reload_wrap)

        -- rename
    elseif key == 'R' then
        ops.rename(path, data.fname, reload_wrap)

        -- move
    elseif key == 'M' then
        local marks = {}
        for i=4, #M.info_table do
            if M.info_table[i].mark == 'm' then
                table.insert(marks, M.info_table[i])
            end
        end
        if #marks == 0 then table.insert(marks, data) end
        ops.move(path, marks, reload_wrap)

        -- set mark
    elseif key == 'm' then
        ops.set_mark(core.buf, M.info_table, line_nr, 'm')
        ops.move_cursor_down(core.buf.bufnr, core.win_id)

        -- set d mark
    elseif key == 'd' then
        ops.set_mark(core.buf, M.info_table, line_nr, 'd')
        ops.move_cursor_down(core.buf.bufnr, core.win_id)

        -- unmark
    elseif key == 'u' then
        ops.set_mark(core.buf, M.info_table, line_nr, '')
        ops.move_cursor_down(core.buf.bufnr, core.win_id)

        -- unmark all
    elseif key == 'U' then
        for i=4, #M.info_table do
            ops.set_mark(core.buf, M.info_table, i+1, '')
        end

        -- invert marks
    elseif key == 'i' then
        for i=4, #M.info_table do
            if M.info_table[i].mark ~= 'd' then
                if M.info_table[i].mark == 'm' then
                    ops.set_mark(core.buf, M.info_table, i+1, '')
                else
                    ops.set_mark(core.buf, M.info_table, i+1, 'm')
                end
            end
        end

        -- do delete on d mark files
    elseif key == 'X' then
        local marks = {}
        for i=4, #M.info_table do
            if M.info_table[i].mark == 'd' then
                table.insert(marks, M.info_table[i])
            end
        end
        if #marks ~= 0 then
            ops.remove(path, marks, reload_wrap)
        else
            vim.notify("No delete marks specified", vim.log.levels.WARN)
            return
        end

        -- reload
    elseif key == 'r' then
        reload_wrap()

        -- shell command
    elseif key == "s!" then
        ops.shell_command(path, reload_wrap)
    end

    -- These keys don't need to reload the buffer
    local no_need_reload_keys = {"CR", 'o', 'm', 'd', 'u', 'U', 'i', 'r'}
    for _, v in ipairs(no_need_reload_keys) do
        if key == v then return end
    end
end



M.determine = function(opts)
    -- Open parent directory
    if opts.args == M.commands[1] then
        M.open_parent_dir()

    -- Open specified directory
    elseif opts.args == M.commands[2] then
        vim.ui.input(
            { prompt = "Open directory: ", default = vim.uv.cwd(), completion = "dir"},
            function(pto)  -- pto = path to open
                if pto == nil then
                    return
                elseif pto == '' then
                    M.open_parent_dir()
                    return
                end

                local stat = vim.uv.fs_stat(pto)
                if not stat then
                    vim.cmd([[echon ' ']])
                    vim.notify("No such directory: " .. pto, vim.log.levels.WARN)
                else
                    if stat.type == "file" then
                        pto = vim.fs.dirname(pto)
                    end
                    M.open_dir(pto)
                end
            end
        )
    else
        vim.notify("[Simdir] Unknow command", vim.log.levels.ERROR)
    end
end

M.setup = function(user_opts)
    if user_opts then
        M.config = vim.tbl_deep_extend("force", M.default_config, user_opts)
    else
        M.config = M.default_config
    end

    core.init_hl_group()

    -- Create an autocommand group
    vim.api.nvim_create_augroup('SimdirCursorHijack', { clear = true })


    vim.api.nvim_create_user_command(
        'Simdir',
        function(opts)
            M.determine(opts)
        end,
        {
            nargs = 1,
            complete = function()
                return M.commands
            end,
        }
    )
end

return M
