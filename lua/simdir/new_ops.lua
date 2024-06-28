local M = {}

local bf = require('simdir.buffer')
local fs = require('simdir.fs')
local hl = require('simdir.highlight')
local op = require('simdir.operations')

M.job_id = nil
M.pid = nil


local function print_and_sleep(msg)
    print(msg)
    vim.fn.timer_start(3750, function() vim.cmd([[echon ' ']]) end)
end

M.touch = function(path)
    path = fs.shorten_path(path)
    local msg = "File created successfully"
    if string.sub(path, -1) ~= '/' then path = path .. '/' end
    vim.ui.input(
        { prompt = "Touch file, Command:\ntouch ", default = path },
        function(cmd)
            if cmd == nil or cmd == '' then
                return
            end
            -- print(cmd)
            cmd = string.format("touch %s", cmd)
            M._run_shell_command(path, cmd, msg)
        end
    )
end

M.mkdir = function(path)
    local msg = "Directory created successfully"
    if string.sub(path, -1) ~= '/' then path = path .. '/' end
    vim.ui.input(
        { prompt = "Create Directory, Command:\nmkdir ", default = path },
        function(cmd)
            if cmd == nil or cmd == '' then
                return
            end
            -- print(cmd)
            cmd = string.format("mkdir -p %s", cmd)
            M._run_shell_command(path, cmd, msg)
        end
    )
end

M.rename = function(fname, path)
    if fname == '.' or fname == ".." then return end

    local msg = "Rename successfully"
    if string.sub(path, -1) ~= '/' then path = path .. '/' end
    vim.ui.input(
        { prompt = string.format("Rename file/dir, Command:\nmv %s ", fname), default = fname },
        function(new_name)
            if new_name == nil or new_name == '' then
                return
            elseif string.sub(new_name, -1) == '/' then
                new_name = string.sub(new_name, 1, -2)
            end
            local cmd = string.format("mv %s %s", fname, path .. new_name)
            M._run_shell_command(path, cmd, msg)
        end
    )
end

M.move = function(marks, path)
    local msg = "Move successfully"
    if string.sub(path, -1) ~= '/' then path = path .. '/' end
    vim.ui.input(
        { prompt = string.format("Move files/dirs, Command:\nmv [marks] %s ", path), default = path },
        function(to)
            if to == nil or to == '' then
                return
            -- elseif fs.get_file_attributes(path .. to).type ~= "directory" then
            --     to = string.sub(to, 1, -2)
            end
            local source = ''
            for _, v in ipairs(marks) do
                source = string.format("%s %s ", source, v.fname)
            end
            local cmd = string.format("mv %s %s", source, to)
            M._run_shell_command(path, cmd, msg)
        end
    )
end

M.reload = function(info_table, old_info_table, padding_line_count)
    local i = 1
    for _, v in ipairs(old_info_table) do
        if info_table[i].full_path == v.full_path then
            info_table[i].mark = v.mark
            i = i + 1
            if i > #info_table then break end
        end
    end
    for j, v in ipairs(info_table) do
        op.set_mark(info_table, j, j+padding_line_count, v.mark)
    end
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
