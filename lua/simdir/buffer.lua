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

    -- Pressing r to reload
    vim.api.nvim_buf_set_keymap(buf, 'n', 'r', ":", {silent=true, noremap=true, desc=""})
    -- Jump to file when hit enter
    vim.api.nvim_buf_set_keymap(buf, 'n', "<CR>", ":lua require('simdir').open_file(false)<CR>", {silent=true, noremap=true, desc="Simdir open file"})
    -- Open in new window
    vim.api.nvim_buf_set_keymap(buf, 'n', "o", ":lua require('simdir').open_file_2()<CR>", {silent=true, noremap=true, desc="Simdir open file in new window"})

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

    return buf
end

M.write_lines = function(buf, s, e, lines)
    vim.api.nvim_buf_set_option(buf, 'modifiable', true)
    vim.api.nvim_buf_set_lines(buf, s, e, false, lines)
    vim.api.nvim_buf_set_option(buf, 'modifiable', false)
end

M.move_cursor = function(last_path, info_table)
    local fname = vim.fn.fnamemodify(last_path, ":t")
    if fname == '' then return end
    for i, data in ipairs(info_table) do
        if data.fname == fname then
            vim.api.nvim_win_set_cursor(M.win, {i+1, data.filename_start-1})
            break
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

    -- Set up autocommands to call the function on cursor movement in normal mode
    vim.api.nvim_create_autocmd('CursorMoved', {
        group = 'SimdirCursorHijack',
        buffer = M.buf.main,
        callback = set_cursor_fixed_column,
    })
end


return M
