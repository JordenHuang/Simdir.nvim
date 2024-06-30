-- TODO:
-- 1. marks
-- 2. shell command enter buffer
-- 3. key maps
local M = {}

local core = require('simdir.dev-core')

M.info_table = {}

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
                    if line ~= '' then
                        vim.schedule(function() vim.notify(line, vim.log.levels.ERROR) end)
                    end
                end
            end,
            on_exit = function(_, code, _) --[[ print("exit with code:", code) return --]] end
        }
    )
    -- Wait the job to exit before we continue
    -- return if exit_code is not 0
    local exit_code = vim.fn.jobwait({job_id})
    if exit_code[1] ~= 0 then return end

    core.buf_open({})
    -- Clear the buffer content
    core.buf:write_lines(0, -1, {})
    -- Write path message
    core.buf:write_lines(0, -1, {path .. ':'})
    -- Highlight the path text
    core.buf:set_hl(core.hl_ns_id, 'DiagnosticOk', 0, 0, #path)

    M.info_table = core.parse_lines(lines, path)
    -- print(vim.inspect(M.info_table))

    for i, line in ipairs(lines) do
        if line ~= '' then
            local data = M.info_table[i]
            local row = data.line_number - 1
            -- print(vim.inspect(data))
            -- print('linenr', linenr)
            -- print('line', line)
            core.buf:write_lines(-1, -1, {line})

            -- Apply highlights
            if data.ftype == 'd' then
                core.buf:set_hl(core.hl_ns_id, 'Simdir_hl_dirname', row, data.fname_hl_s, data.fname_hl_e)
            elseif data.ftype == 'l' then
                core.buf:set_hl(core.hl_ns_id, 'Simdir_hl_symlink', row, data.fname_hl_s, data.fname_hl_e)
                if data.misc.link_to_ftype == 'd' then
                    core.buf:set_hl(core.hl_ns_id, 'Simdir_hl_dirname', row, data.misc.link_hl_s, data.misc.link_hl_e)
                end
            end
        end
    end

    core.cursor_hijack()
end

M.open_parent_dir = function()
    M.open_dir(vim.uv.cwd())
end

M.open_path = function()
    local line_nr = vim.api.nvim_win_get_cursor(0)[1]
    if line_nr == 1 or line_nr == 2 then return end
    local data = M.info_table[line_nr - 1]

    if data.ftype == 'd' then
        if data.fpath == '/' then print(vim.inspect(M.info_table)) end
        M.open_dir(data.fpath)
    elseif data.ftype == 'l' then
        if data.misc.link_to == '-' then
            vim.cmd('edit ' .. data.fpath)
        elseif data.misc.link_to == "broken" then
            vim.notify("Link is broken", vim.log.levels.WARN)
        else
            M.open_dir(data.fpath)
        end
    else
        vim.cmd('edit ' .. data.fpath)
    end
end

return M
