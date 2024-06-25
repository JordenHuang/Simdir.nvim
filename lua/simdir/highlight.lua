local M = {}

M.default_hl_val = {
    dirname = {
        fg = string.format("#%06x",vim.api.nvim_get_hl(0, {name="qfFileName"}).fg),
    },
    symlink = {
        fg = string.format("#%06x",vim.api.nvim_get_hl(0, {name="DiagnosticSignWarn"}).fg),
        -- fg = "#ff0000"
    }
}

M.ns_id = ''

M.init_hl_group = function()
    local val = M.default_hl_val
    local ns_id = vim.api.nvim_create_namespace('Simdir_ns')
    M.ns_id = ns_id
    vim.api.nvim_set_hl(ns_id, 'Simdir_hl_dirname', val.dirname)
    vim.api.nvim_set_hl(ns_id, 'Simdir_hl_symlink', val.symlink)

    -- Active the highlight namespace
    vim.api.nvim_set_hl_ns(ns_id)
end

M.apply_highlight = function(bufnr, hl_group, line, start_col, end_col)
    -- Add the highlight to the specified range
    vim.api.nvim_buf_add_highlight(bufnr, M.ns_id, hl_group, line, start_col, end_col)
end

M.highlight_logic = function(buf, tbl, line_count, start_col_of_filename, line_length)
    if tbl.type == 'd' then
        M.apply_highlight(buf, 'Simdir_dirname', line_count, start_col_of_filename-1, line_length)
    elseif tbl.type == 'l' then
        print('link hl')
        local s = tbl.misc.s
        local e = tbl.misc.e
        M.apply_highlight(buf, 'Simdir_link', line_count, start_col_of_filename-1, s)
        if tbl.misc.link_info == 'd' then
            print('dir hl')
            -- hl.apply_highlight(buf, 'Simdir_dirname', line_count, start_col_of_filename+e-1, #line)
        end
    end

end

return M
