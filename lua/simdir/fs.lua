local M = {}

-- local uv = vim.loop
--
--
-- M.scandir = function(path, callback)
--     local req = uv.fs_scandir(path)
--     local function iter()
--         return uv.fs_scandir_next(req)
--     end
--
--     local files = {}
--     for name in iter do
--         table.insert(files, name)
--     end
--
--     callback(files)
-- end
--
-- M.scandir('..', function(files)
--     for _, file in ipairs(files) do
--         print(file)
--     end
-- end
-- )

local uv = vim.loop

--[[
local function get_file_info(path)
    local stat = uv.fs_stat(path)
    if not stat then return nil end

    local file_info = {
        name = path,
        size = stat.size,
        type = stat.type,
        permissions = stat.mode,
        modified = stat.mtime.sec,
    }

    return file_info
end

local function human_readable_size(size)
    local units = {"B", "K", "M", "G", "T"}
    local unit = 1
    while size >= 1024 and unit < #units do
        unit = unit + 1
        size = size / 1024
    end
    return string.format("%.1f%s", size, units[unit])
end

local function format_file_info(file_info)
    local name = file_info.name
    local size = human_readable_size(file_info.size)
    local file_type = file_info.type == 'directory' and 'd' or '-'
    local permissions = string.format("%o", file_info.permissions)
    local modified = os.date("%b %d %H:%M", file_info.modified)

    return string.format("%s %s %s %s %s", file_type, permissions, size, modified, name)
end

local function scandir(path)
    local req = uv.fs_scandir(path)
    if not req then
        return nil, "Error opening directory: " .. path
    end

    local files = {}
    while true do
        local name, t = uv.fs_scandir_next(req)
        if not name then break end
        table.insert(files, get_file_info(path .. "/" .. name))
    end

    -- Group directories first
    table.sort(files, function(a, b)
        if a.type == b.type then
            return a.name < b.name
        else
            return a.type == 'directory'
        end
    end)

    return files
end

local function open_buffer_with_files(files)
    vim.cmd('vsplit')  -- Open a vertical split
    vim.cmd('enew')    -- Create a new buffer
    vim.bo.buftype = 'nofile'
    vim.bo.bufhidden = 'hide'
    vim.bo.swapfile = false

    local lines = {}
    for _, file in ipairs(files) do
        table.insert(lines, format_file_info(file))
    end

    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end


function M.open_directory(path)
    local files, err = scandir(path)
    if err then
        print(err)
        return
    end

    open_buffer_with_files(files)
end
--]]

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
M.resolve_symlink = function(path)
    local real_path = vim.uv.fs_realpath(path)
    return real_path
end

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



M.parse_line = function(line, start_col_of_filename, path)
    print("path:", path)
    local link_to_name
    local filename = string.sub(line, start_col_of_filename)
    -- print('filename: ' .. filename)
    local file_type = string.sub(line, 1, 1)
    -- print('file type: ' .. file_type)
    local misc = {}

    -- If it's a link file
    local s, e
    if file_type == 'l' then
        s, e = string.find(filename, " -> ", 1, true)
        s = tonumber(s)
        e = tonumber(e)
        link_to_name = string.sub(filename, e+1)
        filename = string.sub(filename, 1, s-1)
        -- print("It's a link:",filename, ';')
        -- print('temp:', link_to_name)
        misc["s"] = s
        misc["e"] = e
    end

    -- Quote filename if it contains spaces
    local temp, _ = string.find(filename, ' ', 1, true)
    if temp then
        filename = "'" .. filename .. "'"
    end

    -- Determine the real_path and display_path
    -- Acutal path of the file or directory
    local real_path
    -- Display path is the line that display on the first line
    local display_path
    -- Check root directory
    if path ~= '/' then
        if filename == ".." then
            real_path = M.trim_last(path)
            display_path = real_path
        elseif file_type == 'l' then
            -- If link file
            real_path = M.resolve_symlink(path .. '/' .. filename)
            local state = M.get_file_attributes(real_path)
            -- Check the link is to a file or directory
            if state.type == "directory" then
                display_path = string.format("%s/%s", path, filename)
                misc["link_info"] = 'd'
            else
                display_path = M.trim_last(real_path)
                misc["link_info"] = '-'
            end
        else
            real_path = string.format("%s/%s", path, filename)
            display_path = path
        end
    else
        if filename == ".." then
            real_path = '/'
            display_path = real_path
        elseif file_type == 'l' then
            -- If link file
            real_path = M.resolve_symlink(path .. '/' .. filename)
            -- Check the link is to a file or directory
            local state = M.get_file_attributes(real_path)
            if state.type == "directory" then
                display_path = '/' .. filename
                misc["link_info"] = 'd'
            else
                display_path = real_path
                misc["link_info"] = '-'
            end
        else
            real_path = '/' .. filename
            display_path = real_path
        end
    end

    misc["hl_start"] = start_col_of_filename
    misc["hl_end"] = string.len(line)
    -- print(vim.inspect(misc))

    return {
        type = file_type,
        name = filename,
        real_path = real_path,
        -- display_path = display_path,
        mark = false,
        misc = misc,
    }
end

-- Stolen from mini.files
-- https://github.com/echasnovski/mini.files/blob/main/lua/mini/files.lua#L2333-L2366
M.normalize_path = function(path) return (path:gsub('/+', '/'):gsub('(.)/$', '%1')) end

M.is_present_path = function(path) return vim.uv.fs_stat(path) ~= nil end

M.child_path = function(dir, name) return M.normalize_path(string.format('%s/%s', dir, name)) end

M.full_path = function(path) return M.normalize_path(vim.fn.fnamemodify(path, ':p')) end

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
M.parse_line_2 = function(line, path)
    local fname, ftype, full_path
    local misc = {}
    local hl_start, hl_end
    if vim.startswith(line, "total") then
        -- Reset the index of the start of a file name
        M.filename_start = -1
        return {}
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
            local state = M.get_file_attributes(full_path)
            -- Check the link is to a file or directory
            if state.type == "directory" then
                misc["link_to"] = 'd'
                misc["link_to_hl_start"] = (M.filename_start - 1) + pos[2]
                misc["link_to_hl_end"] = string.len(line)
            else
                misc["link_to"] = '-'
            end
        else
            full_path = M.full_path(M.child_path(path, fname))
        end
    end
    return {
        fname = fname,
        ftype = ftype,
        full_path = full_path,
        hl_start = hl_start,
        hl_end = hl_end,
        misc = misc,
    }
end




return M
