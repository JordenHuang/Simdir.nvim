local M = {}

M.keymaps = {
    ["<CR>"] = "open",
    ["o"] = "open_split",
    ["-"] = "parent_dir",
    ["T"] = "touch",
    ["+"] = "mkdir",
    ["R"] = "rename",
    ["M"] = "move",
    ["C"] = "copy",
    ["m"] = "mark",
    ["d"] = "d_mark",
    ["u"] = "unmark",
    ["U"] = "unmark_all",
    ["i"] = "invert_mark",
    ["X"] = "remove",
    ["r"] = "reload",
    ["s!"] = "shell_command",
}

M.setup_buf_keymaps = function(buf)
    local rhs
    for k, v in pairs(M.keymaps) do
        rhs = string.format(":lua require('simdir').keys('%s')<CR>", v)
        buf:set_keymap('n', k, rhs, 'Simdir buffer')
    end
end

return M
