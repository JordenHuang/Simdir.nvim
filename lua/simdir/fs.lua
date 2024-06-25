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

-- Function to resolve symlink
M.resolve_symlink = function(path)
    local real_path = uv.fs_realpath(path)
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
    local link_to_name
    local filename = string.sub(line, start_col_of_filename)
    print('filename: ' .. filename)
    local file_type = string.sub(line, 1, 1)
    print('file type: ' .. file_type)
    local misc = {}

    -- If it's a link file
    local s, e
    if file_type == 'l' then
        s, e = string.find(filename, " -> ", 1, true)
        s = tonumber(s)
        e = tonumber(e)
        link_to_name = string.sub(filename, e+1)
        filename = string.sub(filename, 1, s-1)
        print("It's a link:",filename, ';')
        print('temp:', link_to_name)
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
            local state = M.get_file_attributes(path)
            -- Check the link is to a file or directory
            if state.type == "directory" then
                display_path = string.format("%s/%s", path, filename)
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

    print(vim.inspect(misc))
    return {
        type = file_type,
        name = filename,
        real_path = real_path,
        display_path = display_path,
        mark = false,
        misc = misc,
    }
end





return M
