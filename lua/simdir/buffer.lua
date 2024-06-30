-- TODO:
-- use below to create a window for command input
-- I think I might discard the current way of doing file system manipulations
-- Just let the user enter the command when they press the predefine keys,
-- buf with the command and args complete for them
-- They just need to enter the part they need to specified
-- vim.api.nvim_win_set_option(win, 'scrolloff', 0)
-- vim.api.nvim_win_set_height(win, 5)

local M = {}


M.opened_bufs = {}

M.buf = { main=nil, minor=nil }
M.win = false

M.if_buf_is_valid = function(buf_to_check)
    -- If the buffer is never created
    if buf_to_check == false then
        return false
    end

    local flag = false
    -- Check if the previous buffer in buffer-list
    local bufs = vim.api.nvim_list_bufs()
    for _, buf in pairs(bufs) do
        -- print(buf)
        if buf_to_check == buf then
            flag = true
        end
    end

    -- if not flag, means the buffer is not in buffer-list
    if flag then
        -- Check buffer is valid and loaded
        local b = vim.api.nvim_buf_is_loaded(buf_to_check)
        -- print("loaded: ", b)
        if b == true then
            return true
        else
            vim.api.nvim_buf_delete(buf_to_check, {})
        end
    end

    return false
end

-- Check if the buffer is displaying in one of the windows
M.if_buf_present = function(buf)
    if buf == false then
        return false
    end
    local windows = vim.api.nvim_list_wins()
    for _, win in pairs(windows) do
        if vim.api.nvim_win_get_buf(win) == buf then
            return true
        end
    end
    return false
end

M.create_buf = function()
    -- Create a new buffer
    local buf = vim.api.nvim_create_buf(false, false)
    -- Set some options for the buffer
    vim.api.nvim_buf_set_name(buf, "Simdir")
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'buflisted', true)

    M.buf.main = buf
    return buf
end

M.buf_open = function()
    local buf = M.buf.main
    local buf_valid = M.if_buf_is_valid(buf)
    local buf_present = M.if_buf_present(buf)

    -- Create a buffer for the output
    if not buf_valid then
        buf = M.create_buf()
    end

    -- Create a window to display the buffer
    if not buf_present then
        vim.api.nvim_command('topleft split')
        local win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_buf(win, buf)
        M.win = win
    end

    M.buf_set_keymaps(buf)

    return buf
end


M.write_lines = function(buf, s, e, lines)
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(buf, s, e, false, lines)
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

M.move_cursor_on_last_directory = function(last_path, info_table, padding)
    local fname = vim.fn.fnamemodify(last_path, ":t")
    if fname == '' then return end
    for i, data in ipairs(info_table) do
        if data.fname == fname then
            vim.api.nvim_win_set_cursor(M.win, {i+padding, data.filename_start-1})
            return
        end
    end
end


M.cursor_hijack = function(filename_start)
    -- Define a function to set the cursor to a fixed column
    local last_time_row = nil
    local function set_cursor_fixed_column()
        local fix_col = filename_start -- Set the fixed column you want the cursor to stay at
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
    vim.api.nvim_win_set_cursor(0, {3, filename_start-1})

    -- Set up autocommands to call the function on cursor movement in normal mode
    vim.api.nvim_create_autocmd('CursorMoved', {
        group = 'SimdirCursorHijack',
        buffer = M.buf.main,
        callback = set_cursor_fixed_column,
    })
end


M.buf_set_keymaps = function(buf)
    local function h(key)
        return string.format(":lua require('simdir').key_operate('%s')<CR>", key)
    end
    local function opts(desc)
        return {silent=true, noremap=true, desc=desc, nowait=true}
    end
    -- Jump to file when hit enter
    vim.api.nvim_buf_set_keymap(buf, 'n', "<CR>", h("CR"), opts("Simdir open file"))
    -- Open in new window, (Not yet implement)
    vim.api.nvim_buf_set_keymap(buf, 'n', 'o', h('o'), opts("Simdir open file in new window"))
    -- T to touch file
    vim.api.nvim_buf_set_keymap(buf, 'n', 'T', h('T'), opts("Simdir touch file"))
    -- + for create a directory
    vim.api.nvim_buf_set_keymap(buf, 'n', '+', h('+'), opts("Simdir mkdir"))
    -- R to rename
    vim.api.nvim_buf_set_keymap(buf, 'n', 'R', h('R'), opts("Simdir rename file/dir"))
    -- M for move
    vim.api.nvim_buf_set_keymap(buf, 'n', 'M', h('M'), opts("Simdir move file/dir"))
    -- Set mark to a line
    vim.api.nvim_buf_set_keymap(buf, 'n', 'm', h('m'), opts("Simdir set mark"))
    -- Set d mark to a line
    vim.api.nvim_buf_set_keymap(buf, 'n', 'd', h('d'), opts("Simdir set d mark"))
    -- Unmark to a line
    vim.api.nvim_buf_set_keymap(buf, 'n', 'u', h('u'), opts("Simdir unmark"))
    -- Unmark all
    vim.api.nvim_buf_set_keymap(buf, 'n', 'U', h('U'), opts("Simdir unmark all"))
    -- Invert marks
    vim.api.nvim_buf_set_keymap(buf, 'n', 'i', h('i'), opts("Simdir invert marks"))
    -- Delete the d marks files/dirs
    vim.api.nvim_buf_set_keymap(buf, 'n', 'x', h('x'), opts("Simdir delete d mark files"))
    -- Pressing r to reload
    vim.api.nvim_buf_set_keymap(buf, 'n', 'r', h('r'), opts("Simdir reload"))
    -- Run shell command
    vim.api.nvim_buf_set_keymap(buf, 'n', "s!", h("s!"), opts("Simdir run shell command"))

    -- Ctrl+c to kill command
    vim.api.nvim_buf_set_keymap(buf, 'n', "<C-c>", ":lua require('simdir.operations').interrupt_program()<CR>", {silent=true, noremap=true, desc="Simdir interrupt command"})
end

return M
