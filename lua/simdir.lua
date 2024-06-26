-- TODO:
-- [x]1. handle permission denied
-- [ ]2. when go to "..", move cursor on the directory that just leave
-- [x]3. add highlight to first "."
-- [ ]4. clean up highlight.lua

local M = {}

local uv = vim.uv
local fs = require('simdir.fs')
local bf = require('simdir.buffer')
local hl = require('simdir.highlight')


M.default_config = {}

M.commands = {
    "open_parent_dir",  -- Open current working directory
    -- "open_dir",  -- Open specified directory
}

M.PADDING_LINE_COUNT = 3

M.info_table = {}

M.open_dir_test = function(path)
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
                    vim.schedule(function() vim.notify(line, vim.log.levels.ERROR) end)
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

    for i, line in ipairs(lines) do
        if line ~= '' then
            -- Write lines to buffer
            bf.write_lines(buf, -1, -1, {line})
            -- print(line)
            local tbl = fs.parse_line_2(line, path)
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

-- @param: path: string
M.open_dir = function(path)
    print('Path: ' .. path)

    M.info_table = {}

    local buf = bf.buf_open()

    -- Clear the buffer content
    bf.write_lines(buf, 0, -1, {})

    -- Write path message
    bf.write_lines(buf, 0, -1, {path .. ':'})

    local line_count = 0
    local start_col_of_filename = nil

    local function on_output(_, data, _)
        if not data then
            return
        end

        for _, line in ipairs(data) do
            if line ~= '' then
                -- print(line)
                -- Write lines to buffer
                bf.write_lines(buf, -1, -1, {line})

                line_count = line_count + 1
                -- Line 3 is '..'
                if line_count == 3 then
                    start_col_of_filename = fs.get_start_col_of_filename(line)
                end

                if line_count >= 3 then
                    local tbl = fs.parse_line(line, start_col_of_filename, path)
                    table.insert(M.info_table, tbl)

                    if tbl.type == 'd' then
                        hl.apply_highlight(buf, 'Simdir_hl_dirname', line_count, start_col_of_filename-1, string.len(line))
                    elseif tbl.type == 'l' then
                        local s = tbl.misc.s
                        local e = tbl.misc.e
                        hl.apply_highlight(buf, 'Simdir_hl_symlink', line_count, start_col_of_filename-1, start_col_of_filename+s-2)
                        if tbl.misc.link_info == 'd' then
                            hl.apply_highlight(buf, 'Simdir_hl_dirname', line_count, start_col_of_filename+e-1, string.len(line))
                        end
                    end
                end
            end
        end

    end

    local cmd = string.format("ls %s -alh", path)
    vim.fn.jobstart(
        cmd,
        {
            stdout_buffered = true,
            stderr_buffered = true,
            on_stdout = on_output,
            on_stderr = function(_, data, _)
                for _, line in ipairs(data) do
                    print(line)
                end
            end,
            on_exit = function(_, code, _)
                print("exit with code:", code)
                -- print(vim.inspect(M.info_table))
            end
        }
    )
end

M.open_parent_dir = function()
    local path = uv.cwd()
    M.open_dir(path)
end


-- @parm: new_win : boolean
M.open_file = function(new_win)
    local line_nr = vim.api.nvim_win_get_cursor(bf.win)[1]
    line_nr = line_nr - M.PADDING_LINE_COUNT
    if line_nr > 0 then
        local info = M.info_table[line_nr]

        if info.type == 'd' then
            if new_win then
            end
            -- print("go in to:" .. info.real_path)
            M.open_dir(info.real_path)
        elseif info.type == 'l' then
            if info.misc.link_info == '-' then
                if new_win then
                    vim.cmd('rightbelow split')
                end
                vim.cmd('edit ' .. info.real_path)
            else
                -- print("go in to:" .. info.real_path)
                M.open_dir(info.real_path)
            end
        else
            local file_path = info.real_path
            print(file_path)
            if new_win then
                vim.cmd('rightbelow split')
            end
            vim.cmd('edit ' .. file_path)
        end
    end
end

M.open_file_2 = function()
    local line_nr = vim.api.nvim_win_get_cursor(bf.win)[1]
    line_nr = line_nr - 1
    if line_nr > 0 then
        local info = M.info_table[line_nr]

        if info.ftype == 'd' then
            if new_win then
            end
            -- print("go in to:" .. info.real_path)
            M.open_dir_test(info.full_path)
        elseif info.ftype == 'l' then
            if info.misc.link_to == '-' then
                -- if new_win then
                --     vim.cmd('rightbelow split')
                -- end
                vim.cmd('edit ' .. info.full_path)
            else
                -- print("go in to:" .. info.real_path)
                M.open_dir_test(info.full_path)
            end
        else
            print(info.full_path)
            -- if new_win then
            --     vim.cmd('rightbelow split')
            -- end
            vim.cmd('edit ' .. info.full_path)
        end
    end
end



M.determine = function(opts)
    if opts.args == M.commands[1] then
        M.open_parent_dir()
    else
        M.open_dir_test(uv.cwd())
    end
end

M.setup = function(user_opts)
    if user_opts then
        M.config = vim.tbl_deep_extend("force", M.default_config, user_opts)
    else
        M.config = M.default_config
    end

    hl.init_hl_group()

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

    vim.api.nvim_set_keymap('n', '<leader>se', ":Lazy reload simdir.nvim<CR>", {noremap = true})
end

return M
