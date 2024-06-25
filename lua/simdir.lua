-- local scan = require("plenary.scandir")
-- local d = scan.scan_dir('.', {hidden=true, depth=2})
-- print(vim.inspect(d))

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

-- @param: path: string
-- @param: display_path: [string | nil]
M.open_dir = function(path, display_path)
    print('Path: ' .. path)

    M.info_table = {}

    local buf = bf.buf_open()

    -- Clear the buffer content
    bf.write_lines(buf, 0, -1, {})

    -- Write path message
    if display_path then
        bf.write_lines(buf, 0, -1, {display_path .. ':'})
    else
        bf.write_lines(buf, 0, -1, {path .. ':'})
    end

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

                    -- hl.highlight_logic(buf, tbl, line_count, start_col_of_filename, string.len(line))
                    if tbl.type == 'd' then
                        hl.apply_highlight(buf, 'Simdir_hl_dirname', line_count, start_col_of_filename-1, string.len(line))
                        print('start_col_of_filename:', start_col_of_filename)
                        print('#line:', string.len(line))
                    elseif tbl.type == 'l' then
                        print('link hl')
                        local s = tbl.misc.s
                        local e = tbl.misc.e
                        hl.apply_highlight(buf, 'Simdir_hl_link', line_count, start_col_of_filename-1, start_col_of_filename+s-2)
                        print('start_col_of_filename:', start_col_of_filename)
                        print('s:', s)
                        if tbl.misc.link_info == 'd' then
                            print('dir hl')
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
            -- stdout_buffered = false,
            -- stderr_buffered = false,
            on_stdout = on_output,
            on_stderr = on_output,
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
            print("go in to:" .. info.real_path)
            M.open_dir(info.real_path)
        elseif info.type == 'l' then
            if info.misc.link_info == '-' then
                if new_win then
                    vim.cmd('rightbelow split')
                end
                vim.cmd('edit ' .. info.real_path)
            else
                print("go in to:" .. info.real_path)
                M.open_dir(info.real_path, info.display_path)
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



M.determine = function(opts)
    if opts.args == M.commands[1] then
        M.open_parent_dir()
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
