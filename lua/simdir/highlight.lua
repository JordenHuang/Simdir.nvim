local M = {}

M.default_hl_val = {
    dirname = {
        -- fg = string.format("#%06x",vim.api.nvim_get_hl(0, {name="qfFileName"}).fg),
        fg = "#00ff00"
    },
    symlink = {
        -- fg = string.format("#%06x",vim.api.nvim_get_hl(0, {name="DiagnosticSignWarn"}).fg),
        fg = "#ff0000"
    }
}

M.ns_id = ''

M.init_hl_group = function()
    local val = M.default_hl_val
    local ns_id = vim.api.nvim_create_namespace('Simdir_ns')
    M.ns_id = ns_id

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

M.apply_highlight = function(bufnr, hl_group, line, start_col, end_col)
    -- Add the highlight to the specified range
    vim.api.nvim_buf_add_highlight(bufnr, M.ns_id, hl_group, line, start_col, end_col)
end

M.place_sign = function(bufnr, last_sign_id, line, mtype)
    local sign_id
    -- Clear the sign first
    if last_sign_id then
        vim.fn.sign_unplace("Simdir_sign_group", { buffer = bufnr, id = last_sign_id })
    end
    if mtype == 'm' then
        sign_id = vim.fn.sign_place(0, "Simdir_sign_group", "Simdir_m_mark", bufnr, { lnum = line, priority = 10 })
    elseif mtype == 'd' then
        sign_id = vim.fn.sign_place(0, "Simdir_sign_group", "Simdir_d_mark", bufnr, { lnum = line, priority = 10 })
    end
    return sign_id
end


-- M.highlight_logic = function(buf, tbl, line_count, start_col_of_filename, line_length)
--     if tbl.type == 'd' then
--         M.apply_highlight(buf, 'Simdir_dirname', line_count, start_col_of_filename-1, line_length)
--     elseif tbl.type == 'l' then
--         print('link hl')
--         local s = tbl.misc.s
--         local e = tbl.misc.e
--         M.apply_highlight(buf, 'Simdir_link', line_count, start_col_of_filename-1, s)
--         if tbl.misc.link_info == 'd' then
--             print('dir hl')
--             -- hl.apply_highlight(buf, 'Simdir_dirname', line_count, start_col_of_filename+e-1, #line)
--         end
--     end
-- end

return M
