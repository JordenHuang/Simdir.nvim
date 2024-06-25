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
    vim.api.nvim_buf_set_keymap(buf, 'n', "o", ":lua require('simdir').open_file(true)<CR>", {silent=true, noremap=true, desc="Simdir open file in new window"})

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


return M
