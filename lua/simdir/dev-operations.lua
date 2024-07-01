local M = {}

local Buffer = require('simdir.dev-buffer')

-- @pmt : string, pmt is short for prompt
M.create_prompt_window = function()
    local buf = Buffer:new()
    buf:create()
    vim.api.nvim_buf_set_name(buf.bufnr, "Simdir-command")
    buf:set_keymap('n', 'q', ":q<CR>", '')
    buf:set_keymap('n', 'q', ":lua require('simdir.dev-operations').interrupt_program()<CR>", '')
    vim.cmd('belowright split')
    buf:open_in_window()
    vim.api.nvim_win_set_height(0, 5)
    vim.api.nvim_win_set_option(0, "scrolloff", 0)

    -- Set buftype to prompt
    buf:set_options({ buftype = "prompt" })
    return buf
end

M.get_prompt = function(buf, pmt, path, msg, callback)
    -- Write mes
    vim.fn.appendbufline(buf.bufnr, 0, path)
    vim.fn.prompt_setprompt(buf.bufnr, pmt)
    vim.cmd('startinsert')
    vim.fn.prompt_setcallback(buf.bufnr, function(cmd)
        vim.cmd('bdelete!')
        vim.schedule(function()
            vim.cmd('stopinsert')
            -- print(pmt .. cmd)
            cmd = pmt .. cmd
            M._run_shell_command(path, cmd, msg)
            callback()
        end)
    end)
end


M.touch = function(path, callback)
    local pmt = "touch "
    local buf = M.create_prompt_window()
    M.get_prompt(buf, pmt, path, "File touched", callback)

    -- vim.fn.prompt_setcallback(buf.bufnr, function(cmd)
    --     vim.cmd('bdelete!')
    --     vim.cmd('stopinsert')
    --     cmd = pmt .. cmd
    --     M._run_shell_command(path, cmd, "File touched")
    --     callback()
    -- end)
end

M.mkdir = function(path, callback)
    local pmt = "mkdir "
    local buf = M.create_prompt_window()
    M.get_prompt(buf, pmt, path, "Directory created", callback)
end

M.rename = function(path, fname, callback)
    local pmt = string.format("mv %s ", fname)
    local buf = M.create_prompt_window()
    M.get_prompt(buf, pmt, path, "File/Directory renamed", callback)
end

M.move = function(path, marks, callback)
    local pmt = 'mv '
    for _, v in ipairs(marks) do
        pmt = pmt .. v.fname .. ' '
    end
    -- print(pmt)
    local buf = M.create_prompt_window()
    M.get_prompt(buf, pmt, path, string.format("%d Files/Directories moved", #marks), callback)
end

-- Marks
M.set_mark = function(buf, info_table, linenr, mark_type)
    if linenr == 3 or linenr == 4 then return end
    info_table[linenr - 1].mark = mark_type
    buf:set_sign_col(linenr, mark_type)
end


-- Utility functions
-- Move to next line
M.move_cursor_down = function(bufnr, win_id)
    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    if cursor_pos[1] ~= vim.api.nvim_buf_line_count(bufnr) then
        vim.api.nvim_win_set_cursor(win_id, {cursor_pos[1] + 1, cursor_pos[2]})
    end
end

local function print_and_sleep(msg)
    print(msg)
    vim.schedule(function()
        vim.fn.timer_start(3750, function() vim.cmd([[echon ' ']]) end)
    end)
end

M._run_shell_command = function(path, cmd, msg)
    M.job_id = vim.fn.jobstart(
        cmd,
        {
            cwd = path,
            on_stderr = function(_, data, _)
                for _, line in ipairs(data) do
                    if line ~= '' then
                        vim.notify(line, vim.log.levels.ERROR)
                    end
                end
            end,
            on_exit = function(_,code,_)
                if code == 0 then
                    print_and_sleep(msg)
                    -- print(msg)
                    -- vim.schedule(function()
                    --     vim.fn.timer_start(3750, function() vim.cmd([[echon ' ']]) end)
                    -- end)
                    M.job_id = nil
                end
            end
        }
    )
    -- vim.fn.jobwait(M.job_id)
end


M.interrupt_program = function()
    -- Ctrl+c to quit program
    -- see como/buffer.lua
    if M.job_id then
        if vim.fn.jobstop(M.job_id) == 0 then
            local msg = string.format("Job %d has been terminated", M.job_id)
            vim.notify(msg, vim.log.levels.INFO)
        end
    end
    -- if M.pid then
    --     -- print('M.pid:', M.pid)
    --     vim.uv.kill(M.pid, 9)
    -- end
end

return M
