local M = {}

local uv = vim.loop


M.is_file_exist = function(path)
    local state = vim.uv.fs_stat(path)
    if state == nil then return false
    else
        if state.type == "file" then return true end
        return false
    end
end

-- Function to get file attributes
M.get_file_attributes = function(path)
    local stat = uv.fs_stat(path)
    return stat
end

M.resolve_symlink_fname = function(fname)
    local link_from, link_to
    local s, e = string.find(fname, " -> ", 1, true)
    link_from = string.sub(fname, 1, s-1)
    link_to = string.sub(fname, e+1)
    return link_from, link_to, {s, e}
end

-- Function to resolve symlink
M.resolve_symlink = function(path_to_resolve)
    local real_path = vim.uv.fs_realpath(path_to_resolve)
    return real_path
end

-- trim last component (the opposite is `get_basename`)
M.trim_last = function(path)
    -- Remove trailing slash if present
    if path:sub(-1) == '/' then
        path = path:sub(1, -2)
    end

    -- Find the last occurrence of '/'
    local last_slash_index = path:match(".*()/")

    local result
    if last_slash_index then
        result = path:sub(1, last_slash_index-1)
    else
        return path
    end

    if result == '' then
        return '/'
    else
        return result
    end
end


M.get_start_col_of_filename = function(line)
    -- Finds the line that is '..', and calc its start column
    local start_col_of_filename, _ = string.find(line, "..", 1, true)
    return start_col_of_filename
end

M.get_filename = function(path) return M.normalize_path(vim.fn.fnamemodify(path, ':t')) end

-- Stolen from mini.files
-- https://github.com/echasnovski/mini.files/blob/main/lua/mini/files.lua#L2333-L2366
M.normalize_path = function(path) return (path:gsub('/+', '/'):gsub('(.)/$', '%1')) end

M.is_present_path = function(path) return vim.uv.fs_stat(path) ~= nil end

M.child_path = function(dir, name) return M.normalize_path(string.format('%s/%s', dir, name)) end

M.full_path = function(path) return M.normalize_path(vim.fn.fnamemodify(path, ':p')) end

M.shorten_path = function(path)
    -- Replace home directory with '~'
    path = M.normalize_path(path)
    local home_dir = M.normalize_path(vim.loop.os_homedir() or '~')
    local res = path:gsub('^' .. vim.pesc(home_dir), '~')
    return res
end

M.get_basename = function(path) return M.normalize_path(path):match('[^/]+$') end

M.get_parent = function(path)
    path = M.full_path(path)

    -- Deal with top root paths
    if path == '/' then return '/' end

    -- Compute parent
    local res = M.normalize_path(path:match('^.*/'))
    return res
end

M.get_type = function(path)
    if not M.is_present_path(path) then return nil end
    return vim.fn.isdirectory(path) == 1 and 'directory' or 'file'
end

M.has_space = function(text)
    -- Quote filename if it contains spaces
    local s, _ = string.find(text, ' ', 1, true)
    if s then
        return true
    end
    return false
end


M.filename_start = -1
M.parse_line = function(line, path)
    local fname, ftype, full_path
    local misc = {}
    local hl_start, hl_end
    if vim.startswith(line, "total") then
        -- Reset the index of the start of a file name
        M.filename_start = -1
        return nil --{ path = path }
    elseif string.sub(line, -1) == '.' and M.filename_start == -1 then
        M.filename_start = string.len(line)
        fname = '.'
        ftype = 'd'
        full_path = path
        hl_start = (M.filename_start - 1)
        hl_end = M.filename_start
    else
        if M.filename_start == -1 then vim.notify("Invalid filename_start", vim.log.levels.ERROR) end

        hl_start = (M.filename_start - 1)
        hl_end = string.len(line)

        -- Get file name
        fname = string.sub(line, M.filename_start)

        -- Get file type
        ftype = string.sub(line, 1, 1)
        local link_from, link_to, pos
        if ftype == 'l' then
            link_from, link_to, pos = M.resolve_symlink_fname(fname)
            fname = link_from
            hl_end = (M.filename_start - 1) + (pos[1] - 1)
        end

        if M.has_space(fname) then
            fname = "'" .. fname .. "'"
            hl_start = (M.filename_start - 1) - 1
            hl_end = string.len(line) + 1
        end

        -- Get file path
        if fname == ".." then
            full_path = M.get_parent(path)
        elseif ftype == 'l' then
            full_path = M.resolve_symlink(path .. '/' .. fname)
            misc["fname_with_link_from"] = path .. '/' .. fname
            -- when full_path is nil, it means the link is broken
            if full_path == nil then
                full_path = path
                misc["link_to"] = "broken"
            else
                -- Check the link is to a file or directory
                local state = M.get_file_attributes(full_path)
                if state.type == "directory" then
                    misc["link_to"] = 'd'
                    misc["link_to_hl_start"] = (M.filename_start - 1) + pos[2]
                    misc["link_to_hl_end"] = string.len(line)
                else
                    misc["link_to"] = '-'
                end
            end
        else
            full_path = M.full_path(M.child_path(path, fname))
        end
    end
    return {
        filename_start = M.filename_start,
        fname = fname,
        ftype = ftype,
        full_path = full_path,
        hl_start = hl_start,
        hl_end = hl_end,
        misc = misc,
        mark = false
    }
end



-- File manipulations
-- TODO: if these is in operations.lua, then delete them
M.shell_command = function(path)
    vim.ui.input(
        { prompt = "Shell command: \n" },
        function(cmd)
            if cmd == nil or cmd == ''  then
                return
            end
            -- print(cmd)
            M._run_shell_command(path, cmd)
        end
    )
end

M._run_shell_command = function(path, cmd)
    local job_id = vim.fn.jobstart(
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
                    print("Shell command execute successfully")
                    vim.fn.timer_start(3750, function() vim.cmd([[echon ' ']]) end)
                end
            end
        }
    )
end

-- M.create = function(path)
--     vim.ui.input(
--         { prompt = "Create file or directory: ", default = path .. '/' },
--         function(ftc) -- ftc = file to create
--             if ftc == nil or ftc == ''  then
--                 return
--             end
--             if M.is_file_exist(ftc) then
--                 vim.notify("Can NOT create, file already exists", vim.log.levels.WARN)
--             end
--
--         end
--     )
-- end



return M
