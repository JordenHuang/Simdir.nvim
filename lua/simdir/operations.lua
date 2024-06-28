local M = {}

local bf = require('simdir.buffer')
local fs = require('simdir.fs')
local hl = require('simdir.highlight')

M.job_id = nil
M.pid = nil

local function print_and_sleep(msg)
    print(msg)
    vim.fn.timer_start(3750, function() vim.cmd([[echon ' ']]) end)
end

-- Function to split a string by spaces
M.split_by_spaces = function(cmd)
    local result = {}
    for word in string.gmatch(cmd, "%S+") do
        table.insert(result, word)
    end
    return result
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
    if string.sub(path, -1) ~= '/' then path = path .. '/' end
    print(fs.normalize_path(path))
    vim.ui.input(
        { prompt = "Create directory: ", default = path },
        function(new_dir_path)
            if new_dir_path == nil or new_dir_path == '' then
                return
            end
            -- vim.uv.fs_mkdir(new_dir_path, 493, function(err)
            --     if err then
            --         vim.schedule(function()
            --             vim.notify(err, vim.log.levels.ERROR)
            --         end)
            --     else
            --         local msg = "Directory created"
            --         vim.schedule(function() print_and_sleep(msg) end)
            --     end
            -- end)

            -- The default permission is 0o755 (rwxr-xr-x: r/w for the user, readable for others)
            -- convert to decimal is 493 (if using vim.uv.fs_mkdir)
            -- Create parent directory allowing nested names
            -- This allow nested creation
            vim.fn.mkdir(fs.get_parent(new_dir_path), 'p')

            -- Create dir
            if vim.fn.mkdir(new_dir_path) == 1 then
                local msg = "Directory created"
                vim.schedule(function() print_and_sleep(msg) end)
            else
                vim.notify("Can't create directory", vim.log.levels.ERROR)
            end
        end
    )
end

-- @from : string, a path
M.rename = function(from, old_fname)
    local basename = fs.get_basename(from)
    if fs.has_space(basename) then
        from = fs.get_parent(from) .. '/'  .. string.sub(basename, 2, -2)
        old_fname = string.sub(old_fname, 2, -2)
    end
    vim.ui.input(
        { prompt = "Rename to: ", default = from },
        function(to)
            if to == nil or to == '' then
                return
            elseif to == from then
                vim.cmd([[echon ' ']])
                vim.notify("Rename to same name is invalid", vim.log.levels.ERROR)
                return
            end
            -- Move while allowing to create directory
            local success = pcall(function() vim.fn.mkdir(fs.get_parent(to), 'p') end)
            if not success then
                vim.notify("Can't create directory while renaming", vim.log.levels.ERROR)
            end

            success = vim.uv.fs_rename(from, to)
            if success then
                local msg = "Rename file/directory successfully"
                vim.schedule(function() print_and_sleep(msg) end)
            else
                vim.notify("Can't rename file/directory", vim.log.levels.ERROR)
            end
            -- vim.uv.fs_rename(
            --     from,
            --     to,
            --     function(err)
            --         if err then
            --             vim.schedule(function()
            --                 vim.notify(err, vim.log.levels.ERROR)
            --             end)
            --         else
            --             local msg = string.format("Rename/Move '%s' -> '%s' successfully", old_fname, fs.get_filename(to))
            --             vim.schedule(function() print_and_sleep(msg) end)
            --         end
            --     end
            -- )
        end
    )
end

-- TODO: move allow all marked files to be move at once
M.move = function(marks, path)
    vim.ui.input(
        { prompt = "Move to: ", default = path },
        function(to)
            if to == nil or to == '' then
                return
            end
            -- Move while allowing to create directory
            local success = pcall(function() vim.fn.mkdir(fs.get_parent(to), 'p') end)
            if not success then
                vim.notify("Can't create directory while renaming", vim.log.levels.ERROR)
            end

            for _, m in ipairs(marks) do
                if m.ftype == 'l' then
                    success = vim.uv.fs_rename(m.misc.fname_with_link_from, to)
                else
                    success = vim.uv.fs_rename(m.full_path, to)
                end
                print('from', m.full_path)
                if success then
                    local msg = "Move file/directory successfully"
                    vim.schedule(function() print_and_sleep(msg) end)
                else
                    vim.notify("Can't move file/directory", vim.log.levels.ERROR)
                end
            end
        end)
end


-- table is pass by reference
M.set_mark = function(info_table, line_nr, real_line_nr, mark_type)
    -- Don't set mark on the '.' and ".." directory
    if line_nr == 1 or line_nr == 2 then return end
    info_table[line_nr].mark = mark_type

    local bufnr = bf.buf.main
    -- hl.place_sign(bufnr, line_nr, mark_type)
    local sign_id = hl.place_sign(bufnr, info_table[line_nr].misc.sign_id, real_line_nr, mark_type)
    info_table[line_nr].misc.sign_id = sign_id
end

M.unmark_all = function(info_table, real_line_nr)
    for i = 3, #info_table do
        M.set_mark(info_table, i, real_line_nr, '')
    end
end

-- Only invert m mark
M.invert_mark = function(info_table, padding_line_count)
    for i = 3, #info_table do
        if info_table[i].mark ~= 'd' then
            if info_table[i].mark == 'm' then
                M.set_mark(info_table, i, i+padding_line_count, '')
            else
                M.set_mark(info_table, i, i+padding_line_count, 'm')
            end
        end
    end
end





M.shell_command = function(prompt, command, path, msg)
    vim.ui.input(
        { prompt = "Shell command: " },
        function(cmd)
            if cmd == nil or cmd == ''  then
                return
            end
            -- print(cmd)
            M._run_shell_command(path, cmd, msg)
        end
    )
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

-- M._run_shell_command_with_spawn = function(path, cmd, msg)
--     local args = M.split_by_spaces(cmd)
--     cmd = args[1]
--     table.remove(args, 1)
--     print(vim.inspect(args))
--
--     -- Start the job (execute the user command)
--     local handle
--     local stderr = vim.uv.new_pipe(false)
--     handle, M.pid = vim.uv.spawn(
--         cmd,
--         {
--             args = args,
--             cwd = path,
--             stdio = { nil, nil, stderr }
--         },
--         function(exit_code, signal)
--             stderr:read_stop()
--             stderr:close()
--             handle:close()
--             vim.schedule(function()
--                 if exit_code == 0 then
--                     print(msg)
--                     vim.fn.timer_start(3750, function() vim.cmd([[echon ' ']]) end)
--                 end
--                 M.pid = nil
--             end)
--         end
--     )
--
--     stderr:read_start(function(err, data)
--         assert(not err, err)
--         vim.schedule(function()
--             if not data then return end
--             local s = vim.split(data, '\n', {plain=true, trimempty = true})
--             for _, line in ipairs(s) do
--                 vim.notify(line, vim.log.levels.ERROR)
--             end
--         end)
--     end)
-- end

