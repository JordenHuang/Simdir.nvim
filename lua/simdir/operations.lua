local M = {}

local Buffer = require('simdir.buffer')

local ops_buf

local trash_can_dir_name = ".simdir.nvim-trash"

local backup_suffix = "simdir.nvim-backup"

-- @pmt : string, pmt is short for prompt
M.create_prompt_window = function()
    local buf = Buffer:new()
    buf:create()
    vim.api.nvim_buf_set_name(buf.bufnr, "Simdir-command")
    buf:set_keymap('n', 'q', ":bdelete!<CR>", '')

    -- Set buftype to prompt
    buf:set_options({ buftype = "prompt" })
    vim.cmd('belowright split')
    buf:open_in_window()
    vim.api.nvim_win_set_height(0, 3)
    vim.api.nvim_win_set_option(0, "scrolloff", 0)
    ops_buf = buf
end

M.get_prompt = function(pmt, path, msg, reload_callback)
    -- Write mes
    vim.fn.appendbufline(ops_buf.bufnr, 0, string.format("%s, directory: %s", msg.op_name, path))
    vim.fn.prompt_setprompt(ops_buf.bufnr, pmt)
    vim.cmd('startinsert')

    vim.api.nvim_feedkeys(msg.feed, 'i', false)

    vim.fn.prompt_setcallback(ops_buf.bufnr, function(cmd)
        -- Modify cmd only if pmt is in commands list
        local commands = {"touch", "mkdir", "mv", "rm", "cp"}
        for _, v in ipairs(commands) do
            if pmt == v then
                cmd = vim.fn.fnameescape(cmd)
                break
            end
        end

        vim.cmd('bdelete!')
        cmd = pmt .. cmd
        M._run_shell_command(path, cmd, msg.msg)
        vim.schedule(function()
            vim.cmd('stopinsert')
            reload_callback()
-- print("after callback")
        end)
-- print("after sche")
    end)

    vim.fn.prompt_setinterrupt(ops_buf.bufnr, function()
        vim.cmd('bdelete!')
        vim.cmd('stopinsert')
    end)
end


M.touch = function(path, reload_callback)
    local pmt = "touch "
    local msg = { op_name="Touch", feed='', msg="File touched" }
    M.create_prompt_window()
    M.get_prompt(pmt, path, msg, reload_callback)

    -- vim.fn.prompt_setcallback(buf.bufnr, function(cmd)
    --     vim.cmd('bdelete!')
    --     vim.cmd('stopinsert')
    --     cmd = pmt .. cmd
    --     M._run_shell_command(path, cmd, "File touched")
    --     callback()
    -- end)
end

M.mkdir = function(path, reload_callback)
    local pmt = "mkdir "
    local msg = { op_name="Create directory", feed=path..'/', msg="Directory created" }
    M.create_prompt_window()
    M.get_prompt(pmt, path, msg, reload_callback)
end

M.rename = function(path, fname, reload_callback)
    local pmt = string.format("mv %s ", vim.fn.fnameescape(fname))
    local msg = { op_name="Rename", feed=vim.fn.fnameescape(fname), msg="File/Directory renamed"}
    M.create_prompt_window()
    M.get_prompt(pmt, path, msg, reload_callback)
end

M.move = function(path, marks, reload_callback)
    local pmt = string.format('mv -b --suffix=%s ', backup_suffix)
    for _, v in ipairs(marks) do
        pmt = pmt .. vim.fn.fnameescape(v.fname) .. ' '
    end
    local msg = { op_name="Move", feed=path..'/', msg=string.format("%d Files/Directories moved", #marks) }
    -- print(pmt)
    M.create_prompt_window()
    M.get_prompt(pmt, path, msg, reload_callback)
end

M.copy = function(path, marks, reload_callback)
    local pmt = string.format('cp -rb --suffix=%s ', backup_suffix)
    for _, v in ipairs(marks) do
        pmt = pmt .. vim.fn.fnameescape(v.fname) .. ' '
    end
    local msg = { op_name="Copy", feed=path..'/', msg=string.format("%d Files/Directories copied", #marks) }
    -- print(pmt)
    M.create_prompt_window()
    M.get_prompt(pmt, path, msg, reload_callback)
end

-- Marks
M.set_mark = function(buf, info_table, linenr, mark_type)
    if linenr == 3 or linenr == 4 then return end
    info_table[linenr - 1].mark = mark_type
    buf:set_sign_col(linenr, mark_type)
end

M.remove = function(path, marks, reload_callback, use_trash_can)
    local pmt = 'rm -r '
    if use_trash_can then
        pmt = 'mv '
    end

    for _, v in ipairs(marks) do
        pmt = pmt .. vim.fn.fnameescape(v.fname) .. ' '
    end

    if use_trash_can then
        -- Make sure the trash can exists
        local dirname = string.format('%s%s', vim.fn.fnamemodify('~', ":p"), trash_can_dir_name)
        vim.fn.mkdir( dirname, 'p')
        pmt = pmt .. dirname
    end

    local msg = { op_name="Remove", feed='', msg=string.format("%d files/directories removed", #marks) }
    M.create_prompt_window()
    M.get_prompt(pmt, path, msg, reload_callback)
end

M.shell_command = function(path, reload_callback)
    local msg = { op_name="Shell command", feed='', msg="Command executed"}
    M.create_prompt_window()
    M.get_prompt('', path, msg, reload_callback)
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
-- print("after timer")
    end)
-- print("after sche, in print and sleep")
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
                    M.job_id = nil
                end
            end
        }
    )
    -- local exit_code = vim.fn.jobwait({M.job_id}, 2000)
    -- if exit_code[1] == -1 then vim.notify("Timeout exceed", vim.log.levels.WARN) end
end


-- Unused function
M.interrupt_program = function()
    -- Quit program
    if M.job_id then
        if vim.fn.jobstop(M.job_id) == 0 then
            local msg = string.format("Job %d has been terminated", M.job_id)
            vim.notify(msg, vim.log.levels.INFO)
        end
    end
end

return M
