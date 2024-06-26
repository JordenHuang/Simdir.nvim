-- TODO:
-- [x]1. handle permission denied
-- [x]2. when go to "..", move cursor on the directory that just leave
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
    "open_dir",  -- Open specified directory
}

M.PADDING_LINE_COUNT = 3

M.info_table = {}


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
    hl.apply_highlight(buf, 'DiagnosticOk', 0, 0, #path)

    for i, line in ipairs(lines) do
        if line ~= '' then
            -- Write lines to buffer
            bf.write_lines(buf, -1, -1, {line})
            -- print(line)
            local tbl = fs.parse_line(line, path)
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
    bf.cursor_hijack(M.info_table[2].filename_start)
end

M.open_parent_dir = function()
    local path = uv.cwd()
    M.open_dir(path)
end



M.open_file = function()
    local line_nr = vim.api.nvim_win_get_cursor(bf.win)[1]
    line_nr = line_nr - 1
    if line_nr > 0 then
        local info = M.info_table[line_nr]

        if info.ftype == 'd' then
            if new_win then
            end
            -- print("go in to:" .. info.real_path)
            local last_path = M.info_table[2].full_path
            M.open_dir(info.full_path)
            if info.fname == ".." then
                bf.move_cursor(last_path, M.info_table)
            end
        elseif info.ftype == 'l' then
            if info.misc.link_to == '-' then
                -- if new_win then
                --     vim.cmd('rightbelow split')
                -- end
                vim.cmd('edit ' .. info.full_path)
            else
                -- print("go in to:" .. info.real_path)
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
                    vim.notify("No such directory: " .. pto, vim.log.levels.ERROR)
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
