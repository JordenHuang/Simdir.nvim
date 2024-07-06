local M = {}

local Buffer = require('simdir.buffer')
local kmap = require('simdir.keymap')

M.buf = Buffer:new()

M.hl_ns_id = nil

M.fname_start_col = nil

-- Buffer part

M.buf_open = function()
    if not M.buf:is_loaded() then
        M.buf:create()
        -- vim.cmd('split')
    end
    vim.api.nvim_buf_set_name(M.buf.bufnr, "Simdir")
    M.buf:set_options({
        buftype = "nofile",
        modifiable = false,
        swapfile = false,
        buflisted = true,
    })

    kmap.setup_buf_keymaps(M.buf)

    M.buf:open_in_window()
    -- M.win_id = vim.api.nvim_get_current_win()
end

M.move_cursor_on_last_directory = function(last_path, info_table)
    local fname = vim.fn.fnamemodify(last_path, ":t")
    if fname == '' then return end
    for _, data in ipairs(info_table) do
        if data.fname == fname then
            vim.api.nvim_win_set_cursor(0, {data.line_number, M.fname_start_col-1})
            return
        end
    end
end


M.cursor_hijack = function()
    -- Define a function to set the cursor to a fixed column
    local last_time_row = nil
    local function set_cursor_fixed_column()
        local fix_col = M.fname_start_col -- Set the fixed column you want the cursor to stay at
        local cursor = vim.api.nvim_win_get_cursor(0)

        local row, col = cursor[1], cursor[2]
        col = fix_col - 1 -- `win_set_cursor` expects 0-based column index
        if row ~= last_time_row then
            if row > 2 then
                vim.api.nvim_win_set_cursor(0, {row, col})
            else
                vim.api.nvim_win_set_cursor(0, {row, 0})
            end
        end
        last_time_row = row
    end

    -- Set the cursor position first
    vim.api.nvim_win_set_cursor(0, {3, M.fname_start_col-1})

    -- Set up autocommands to call the function on cursor movement in normal mode
    vim.api.nvim_create_autocmd('CursorMoved', {
        group = 'Simdir_augroup',
        buffer = M.buf.bufnr,
        callback = set_cursor_fixed_column,
    })
end

-- End Buffer part


-- Highlight part
M.init_hl_group = function()
    local ns_id = vim.api.nvim_create_namespace('Simdir_ns')
    M.hl_ns_id = ns_id

    local hl_group = "def link Simdir_hl_dirname qfFileName"
    vim.cmd.highlight(hl_group)
    hl_group = "def link Simdir_hl_symlink DiagnosticWarn"
    vim.cmd.highlight(hl_group)

    -- hl_group = "def link Simdir_hl_m_mark DiagnosticInfo"
    -- vim.cmd.highlight(hl_group)
    -- hl_group = "def link Simdir_hl_d_mark DiagnosticError"
    -- vim.cmd.highlight(hl_group)
    vim.fn.sign_define("Simdir_m_mark", { text = "m", texthl = "DiagnosticInfo", linehl = "DiagnosticInfo" })
    vim.fn.sign_define("Simdir_d_mark", { text = "D", texthl = "DiagnosticError", linehl = "DiagnosticError" })
end
-- EndHighlight part


-- Core functions
-- @lines : table
M.parse_lines = function(lines, path)
    -- Remove trailing slash if present
    if path ~= '/' and path:sub(-1) == '/' then path = path:sub(1, -2) end

    local info_table = {}
    local fname_start_col, line_number
    local fname, ftype, fpath, fname_hl_s, fname_hl_e
    local misc = {}
    local line_info = {}
    for i, line in ipairs(lines) do
        if line ~= '' then
            line_info = {}
            line_number = i + 1
            if i == 1 then
                line_info = { line_number = line_number }
            elseif i == 2 then
                fname_start_col = string.len(line)
                M.fname_start_col = fname_start_col
                line_info = {
                    line_number = line_number,
                    fname = '.',
                    ftype = 'd',
                    fpath = path,
                    fname_hl_s = (fname_start_col- 1),
                    fname_hl_e = fname_start_col,
                }
            else
                fname, ftype, fpath, fname_hl_s, fname_hl_e = nil, nil, nil, nil, nil
                misc = {}

                -- Get file name
                fname = string.sub(line, fname_start_col)

                -- Get file type
                ftype = string.sub(line, 1, 1)

                -- Get highlight position
                fname_hl_s = (fname_start_col - 1)
                fname_hl_e = string.len(line)

                if ftype == 'l' then
                    local s, e = string.find(fname, " -> ", 1, true)
                    fname = string.sub(fname, 1, s-1)
                    fname_hl_e = (fname_start_col - 1) + (s - 1)
                    misc.link_hl_s = (fname_start_col - 1) + e
                    misc.link_hl_e = string.len(line)
                end

                -- Check fname has space in it or not
                local sps, _ = string.find(fname, ' ', 1, true)
                -- if sps then
                --     fname = "'" .. fname .. "'"
                -- end

                -- Get file path
                if fname == ".." then
                    fpath = vim.fs.dirname(path)
                    fpath = vim.fn.fnamemodify(fpath, ":p:h")
                elseif ftype == 'l' then
                    fpath = vim.uv.fs_realpath(path .. '/' .. fname)
                    -- TODO: if the path is '/', then it will contain two '/'
                    misc.link_from = path .. '/' .. fname
                    -- when full_path is nil, it means the link is broken
                    if fpath == nil then
                        fpath = path
                        misc.link_to_ftype = "broken"
                    else
                        local link_to_type = vim.uv.fs_stat(fpath).type
                        if link_to_type == "directory" then
                            misc.link_to_ftype = 'd'
                        else
                            misc.link_to_ftype = '-'
                        end
                    end
                else
                    if path == '/' then
                        fpath = path .. fname
                    else
                        fpath = path .. '/' .. fname
                    end
                end

                line_info = {
                    line_number = line_number,
                    fname = fname,
                    ftype = ftype,
                    fpath = fpath,
                    fname_hl_s = fname_hl_s,
                    fname_hl_e = fname_hl_e,
                    mark = '',
                    misc = misc
                }
            end
            table.insert(info_table, line_info)
        end
    end
    return info_table
end
-- End Core functions

return M
