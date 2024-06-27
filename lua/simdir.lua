-- TODO:
-- [x]1. handle permission denied
-- [x]2. when go to "..", move cursor on the directory that just leave
-- [x]3. add highlight to first "."
-- [ ]4. clean up highlight.lua
-- [ ]5. add highlight to mark, d mark

local M = {}

local uv = vim.uv
local fs = require('simdir.fs')
local bf = require('simdir.buffer')
local hl = require('simdir.highlight')
local op = require('simdir.operations')


M.default_config = {}

M.commands = {
    "open_parent_dir",  -- Open current working directory
    "open_dir",  -- Open specified directory
}

M.info_table = {}

M.PADDING_LINE_COUNT = 2

-- @param: path: string
M.open_dir = function(path)
    local lines
    local cmd = string.format("ls %s -alh", path)
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
            on_exit = function(_, code, _)
                -- print("exit with code:", code)
                -- print(vim.inspect(M.info_table))
                return
            end
        }
    )
    -- return if exit_code is not 0
    local exit_code = vim.fn.jobwait({job_id})
    if exit_code[1] ~= 0 then return end

    -- print('Path: ' .. path)
    M.info_table = {}

    local buf = bf.buf_open()

    -- Clear the buffer content
    bf.write_lines(buf, 0, -1, {})
    -- Write path message
    bf.write_lines(buf, 0, -1, {path .. ':'})
    -- Highlight the path text
    hl.apply_highlight(buf, 'DiagnosticOk', 0, 0, #path)

    for i, line in ipairs(lines) do
        if line ~= '' then
            -- Write lines to buffer
            bf.write_lines(buf, -1, -1, {line})
            -- print(line)
            local tbl = fs.parse_line(line, path)
            if tbl ~= nil then
                table.insert(M.info_table, tbl)
                -- print(vim.inspect(tbl))
                if tbl.ftype == 'd' then
                    hl.apply_highlight(buf, 'Simdir_hl_dirname', i, tbl.hl_start, tbl.hl_end)
                elseif tbl.ftype == 'l' then
                    hl.apply_highlight(buf, 'Simdir_hl_symlink', i, tbl.hl_start, tbl.hl_end)
                    if tbl.misc.link_to == 'd' then
                        hl.apply_highlight(buf, 'Simdir_hl_dirname', i, tbl.misc.link_to_hl_start, tbl.misc.link_to_hl_end)
                    end
                end
            end
        end
    end
    bf.cursor_hijack(M.info_table[1].filename_start)
end

M.open_parent_dir = function()
    local path = uv.cwd()
    M.open_dir(path)
end



M.open_file = function()
    local line_nr = vim.api.nvim_win_get_cursor(bf.win)[1]
    line_nr = line_nr - M.PADDING_LINE_COUNT
    if line_nr <= 0 then return end

    local info = M.info_table[line_nr]
    if info.ftype == 'd' then
        local last_path = M.info_table[1].full_path
        M.open_dir(info.full_path)
        -- Move cursor to the directory that just exited
        if info.fname == ".." then
            bf.move_cursor_on_last_directory(last_path, M.info_table, M.PADDING_LINE_COUNT)
        end
    elseif info.ftype == 'l' then
        if info.misc.link_to == '-' then
            vim.cmd('edit ' .. info.full_path)
        elseif info.misc.link_to == "broken" then
            vim.notify("Link is broken", vim.log.levels.WARN)
        else
            M.open_dir(info.full_path)
        end
    else
        print(info.full_path)
        -- if new_win then
        --     vim.cmd('rightbelow split')
        -- end
        vim.cmd('edit ' .. info.full_path)
    end
end

-- @key : string
M.key_operate = function(key)
    local real_line_nr = vim.api.nvim_win_get_cursor(bf.win)[1]
    local line_nr = real_line_nr - M.PADDING_LINE_COUNT
    if line_nr <= 0 then return end

    local info = M.info_table[line_nr]
    local path = M.info_table[1].full_path

    -- open file or directory, (don't know why "<CR>" string doesn't work)
    if key == 'o' or key == "CR" then
        M.open_file()

        -- touch command, for creating empty file
    elseif key == 'T' then
        op.touch(path)

        -- mkdir command
    elseif key == '+' then
        op.mkdir(path)

        -- rename
    elseif key == 'R' then
        if info.ftype == 'l' then
            op.rename(info.misc.fname_with_link_from, info.fname)
        else
            op.rename(info.full_path, info.fname)
        end

        -- move
    elseif key == 'M' then
        local marks = {}
        for _, v in ipairs(M.info_table) do
            if v.mark == 'm' then
                table.insert(marks, v)
            end
        end
        print(vim.inspect(marks))
        if #marks == 0 then
            if info.ftype == 'l' then
                op.rename(info.misc.fname_with_link_from, info.fname)
            else
                op.rename(info.full_path, info.fname)
            end
        else
            op.move(marks, path)
        end
        -- vim.notify("TODO: M for move, allow mark", vim.log.levels.WARN)

        -- set mark
    elseif key == 'm' then
        op.set_mark(M.info_table, line_nr, real_line_nr, 'm')
        print(vim.inspect(M.info_table))
        -- vim.notify("TODO: m for mark", vim.log.levels.WARN)

        -- set d mark
    elseif key == 'd' then
        op.set_mark(M.info_table, line_nr, real_line_nr, 'd')
        print(vim.inspect(M.info_table))
        -- vim.notify("TODO: d for d mark", vim.log.levels.WARN)

        -- unmark
    elseif key == 'u' then
        op.set_mark(M.info_table, line_nr, real_line_nr, '')
        print(vim.inspect(M.info_table))
        -- vim.notify("TODO: u for unmark", vim.log.levels.WARN)

        -- unmark all
    elseif key == 'U' then
        op.unmark_all(M.info_table, real_line_nr)
        -- vim.notify("TODO: U for unmark all", vim.log.levels.WARN)

        -- invert marks
    elseif key == 'i' then
        op.invert_mark(M.info_table, M.PADDING_LINE_COUNT)
        print(vim.inspect(M.info_table))
        -- vim.notify("TODO: i for invert marks", vim.log.levels.WARN)

        -- do delete on d mark files
    elseif key == 'x' then
        vim.notify("TODO: x for delete on d mark files", vim.log.levels.WARN)

        -- reload
    elseif key == 'r' then
        M.open_dir(M.info_table[1].full_path)
        -- vim.notify("TODO: r for reload", vim.log.levels.WARN)
        -- vim.api.nvim_buf_set_keymap(bf.buf, 'n', 'r', ":echo 'TODO'<CR>", {silent=true, noremap=true, desc=""})

        -- shell command
    elseif key == "s!" then
        fs.shell_command(M.info_table[1].full_path)

    end

    -- These keys don't need to reload the buffer
    local no_need_reload_keys = {'o', "CR", 'm', 'd', 'u', 'U', 'i', 'r'}
    for _, v in ipairs(no_need_reload_keys) do
        if key == v then return end
    end

    -- save last info_table
    local last_info_table = M.info_table
    -- reload
    M.open_dir(M.info_table[1].full_path)
    -- Handle x key, it needs reload, but m marks should remain
    if key == 'x' then
        local i = 1
        for _, data in ipairs(last_info_table) do
            if M.info_table[i].full_path == data.full_path then
                M.info_table[i].mark = data.mark
                M.info_table[i].misc.sign_id = data.misc.sign_id
                i = i + 1
            end
        end
    else
        for i, data in ipairs(last_info_table) do
            M.info_table[i].mark = data.mark
        end
    end

    -- TODO: maybe add a "You might need to reload" in the open_dir function, because if the buffer is not update
    -- the ls command will throw error
end









M.determine = function(opts)
    -- Open parent directory
    if opts.args == M.commands[1] then
        M.open_parent_dir()
    -- Open specified directory
    elseif opts.args == M.commands[2] then
        vim.ui.input(
            { prompt = "Open directory: ", default = uv.cwd(), completion = "dir"},
            function(pto)  -- pto = path to open
                if pto == nil then
                    return
                elseif pto == '' then
                    M.open_parent_dir()
                    return
                end

                local stat = uv.fs_stat(pto)
                if not stat then
                    vim.cmd([[echon ' ']])
                    vim.notify("No such directory: " .. pto, vim.log.levels.WARN)
                else
                    if stat.type == "file" then
                        pto = fs.trim_last(pto)
                    end
                    M.open_dir(pto)
                end
            end
        )
    end
end

M.setup = function(user_opts)
    if user_opts then
        M.config = vim.tbl_deep_extend("force", M.default_config, user_opts)
    else
        M.config = M.default_config
    end

    hl.init_hl_group()

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

    -- TODO: remove it
    vim.api.nvim_set_keymap('n', '<leader>se', ":Lazy reload simdir.nvim<CR>", {noremap = true})
end

return M
