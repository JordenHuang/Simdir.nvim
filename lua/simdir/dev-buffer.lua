local Buffer = {}
Buffer.__index = Buffer

function Buffer:new()
    local obj = setmetatable({}, self)
    return obj
end

-- Create a new buffer
function Buffer:create()
    self.bufnr = vim.api.nvim_create_buf(false, true)
    return self.bufnr
end

-- Set buffer options
function Buffer:set_options(options)
    for key, value in pairs(options) do
        vim.api.nvim_buf_set_option(self.bufnr, key, value)
    end
end

-- Open buffer in a window
function Buffer:open_in_window()
    vim.api.nvim_set_current_buf(self.bufnr)
end

-- Check is buffer is loaded and valid
function Buffer:is_loaded()
    if self.bufnr == nil then return false end
    local valid = vim.api.nvim_buf_is_loaded(self.bufnr)
    if valid == true then return true
    else
        vim.api.nvim_buf_delete(self.bufnr, {})
        return false
    end
end

-- Set buffer local keymaps
function Buffer:set_keymap(mode, lhs, rhs, desc)
    local opts = { silent=true, noremap=true, desc=desc, nowait=true }
    vim.api.nvim_buf_set_keymap(self.bufnr, mode, lhs, rhs, opts)
end

-- Write lines
function Buffer:write_lines(s, e, lines)
    vim.api.nvim_buf_set_option(self.bufnr, 'modifiable', true)
    vim.api.nvim_buf_set_lines(self.bufnr, s, e, false, lines)
    vim.api.nvim_buf_set_option(self.bufnr, 'modifiable', false)
end

-- Add highlight
-- @row : number, zero based
function Buffer:set_hl(ns_id, hl_group, row, start_col, end_col)
    -- Add the highlight to the specified range
    vim.api.nvim_buf_add_highlight(self.bufnr, ns_id, hl_group, row, start_col, end_col)
end

return Buffer
