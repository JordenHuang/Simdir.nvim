--TODO:
-- 1. move keys to action.lua, sperate them in to different functions
-- 2. understanding why and when to add fnameescape
local M = {}

local core = require('simdir.core')
local kmap = require('simdir.keymap')
local ops = require('simdir.operations')


M.config = {}

local default_config = {
    default_file_explorer = true,
    use_trash_can_when_remove = true,
    keymaps = kmap.keymaps
}

M.commands = {
    "open_parent_dir",  -- Open current working directory
    "open_dir",  -- Open specified directory
    "open_last", -- Open last simdir buffer
}

M.info_table = {}

M.open_dir = function(path)
    local lines
    local cmd = string.format([[ls %s -alh]], vim.fn.fnameescape(path))
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
    -- Wait the job to exit before we continue, timeout is 2 seconds
    -- return if exit_code is not 0
    local exit_code = vim.fn.jobwait({job_id}, 2000)
    if exit_code[1] ~= 0 then return end

    core.buf_open()
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

M.open_last = function()
    local flag = true
    if not core.buf:is_loaded() then flag = false end
    local bufs = vim.api.nvim_list_bufs()
    if flag then
        for _, v in ipairs(bufs) do
            if core.buf.bufnr == v then
                vim.api.nvim_win_set_buf(0, v)
                return
            end
        end
    end
    vim.notify("[Simdir] No last simdir buffer", vim.log.levels.WARN)
    local choice = vim.fn.confirm("Open parent directory?", "&y\n&n\n")
    if choice == 1 then M.open_parent_dir() end
end


local last_win

M.open_path = function(data, open_in_cur_win)
    if data.ftype == 'd' then
        local last_path = M.info_table[2].fpath
        M.open_dir(data.fpath)
        if data.fname == ".." then
            core.move_cursor_on_last_directory(last_path, M.info_table)
        end
    elseif data.ftype == 'l' then
        if data.misc.link_to_ftype == '-' then
            if not open_in_cur_win then
                if last_win and vim.api.nvim_win_is_valid(last_win) then
                    vim.api.nvim_set_current_win(last_win)
                else
                    vim.cmd('belowright split')
                end
                vim.cmd('edit ' .. data.fpath)
                last_win = vim.api.nvim_get_current_win()
            else
                vim.cmd('edit ' .. data.fpath)
            end
        elseif data.misc.link_to_ftype == "broken" then
            vim.notify("Link is broken", vim.log.levels.WARN)
        else
            local last_path = M.info_table[2].fpath
            M.open_dir(data.fpath)
            if data.fname == ".." then
                core.move_cursor_on_last_directory(last_path, M.info_table)
            end
        end
    else
        if not open_in_cur_win then
            if last_win and vim.api.nvim_win_is_valid(last_win) and last_win ~= vim.api.nvim_get_current_win() then
                vim.api.nvim_set_current_win(last_win)
            else
                vim.cmd('belowright split')
            end
            vim.cmd('edit ' .. data.fpath)
            last_win = vim.api.nvim_get_current_win()
        else
            vim.cmd('edit ' .. data.fpath)
        end
    end
end

M.reload_wrap = function(path)
-- print("before reload wrap")
    return vim.schedule_wrap(function()
        local prev_info_table = M.info_table
        M.open_dir(path)
        -- Copy marks
        local i = 1
        for j = 1, #prev_info_table do
            if M.info_table[i].fpath == prev_info_table[j].fpath then
                M.info_table[i].mark = prev_info_table[j].mark
                i = i + 1
            end
            if i > #M.info_table then break end
        end
        -- Set sign column
        for j, _ in ipairs(M.info_table) do
            ops.set_mark(core.buf, M.info_table, j+1, M.info_table[j].mark)
        end
-- print("inside and after reload wrap")
    end)
end

M.keys = function(key)
    if vim.api.nvim_get_current_buf() ~= core.buf.bufnr then return end
    local win_id = vim.api.nvim_get_current_win()

    local path = M.info_table[2].fpath

    local cursor_pos = vim.api.nvim_win_get_cursor(0)
    local line_nr = cursor_pos[1]
    if line_nr == 1 or line_nr == 2 then return end
    local data = M.info_table[line_nr - 1]

    local reload_wrap = M.reload_wrap(path)
    -- open file or directory
    if key == "open" then
        M.open_path(data, true)

        -- open file in split window
    elseif key == "open_split" then
        M.open_path(data, false)

        -- open parent dir, go up parent dir. Open the ".."
    elseif key == "parent_dir" then
        M.open_path(M.info_table[3], true)

        -- touch command, for creating empty file
    elseif key == "touch" then
        ops.touch(path, reload_wrap)

        -- mkdir command
    elseif key == "mkdir" then
        ops.mkdir(path, reload_wrap)

        -- rename
    elseif key == "rename" then
        ops.rename(path, data.fname, reload_wrap)

        -- move
    elseif key == "move" then
        local marks = {}
        for i=4, #M.info_table do
            if M.info_table[i].mark == 'm' then
                table.insert(marks, M.info_table[i])
            end
        end
        if #marks == 0 then table.insert(marks, data) end
        ops.move(path, marks, reload_wrap)

        -- copy
    elseif key == "copy" then
        local marks = {}
        for i=4, #M.info_table do
            if M.info_table[i].mark == 'm' then
                table.insert(marks, M.info_table[i])
            end
        end
        if #marks == 0 then table.insert(marks, data) end
        ops.copy(path, marks, reload_wrap)

        -- set mark
    elseif key == "mark" then
        ops.set_mark(core.buf, M.info_table, line_nr, 'm')
        ops.move_cursor_down(core.buf.bufnr, win_id)

        -- set d mark
    elseif key == "d_mark" then
        ops.set_mark(core.buf, M.info_table, line_nr, 'd')
        ops.move_cursor_down(core.buf.bufnr, win_id)

        -- unmark
    elseif key == "unmark" then
        ops.set_mark(core.buf, M.info_table, line_nr, '')
        ops.move_cursor_down(core.buf.bufnr, win_id)

        -- unmark all
    elseif key == "unmark_all" then
        for i=4, #M.info_table do
            ops.set_mark(core.buf, M.info_table, i+1, '')
        end

        -- invert marks
    elseif key == "invert_mark" then
        for i=4, #M.info_table do
            if M.info_table[i].mark ~= 'd' then
                if M.info_table[i].mark == 'm' then
                    ops.set_mark(core.buf, M.info_table, i+1, '')
                else
                    ops.set_mark(core.buf, M.info_table, i+1, 'm')
                end
            end
        end

        -- do delete on d mark files
    elseif key == "remove" then
        local marks = {}
        for i=4, #M.info_table do
            if M.info_table[i].mark == 'd' then
                table.insert(marks, M.info_table[i])
            end
        end
        if #marks ~= 0 then
            if M.config.use_trash_can_when_remove then
                ops.remove(path, marks, reload_wrap, true)
            else
                ops.remove(path, marks, reload_wrap, false)
            end
        else
            vim.notify("No delete marks specified", vim.log.levels.WARN)
            return
        end

        -- reload
    elseif key == "reload" then
        reload_wrap()

        -- shell command
    elseif key == "shell_command" then
        ops.shell_command(path, reload_wrap)
    end

    -- These keys don't need to reload the buffer
    local no_need_reload_keys = {"open", 'open_split', 'mark', 'd_mark', 'unmark', 'unmark_all', 'invert_mark', 'reload'}
    for _, v in ipairs(no_need_reload_keys) do
        if key == v then return end
    end
end



M.determine = function(opts)
    local args = {}
    for str in string.gmatch(opts.args, "%S+") do
        table.insert(args, str)
    end

    -- Open parent directory
    if args[1] == M.commands[1] then
        M.open_parent_dir()

    -- Open specified directory
    elseif args[1] == M.commands[2] then
        if #args == 2 then
            args[2] = vim.fn.fnamemodify(vim.fs.dirname(args[2]), ":p")
            local stat = vim.uv.fs_stat(args[2])
            if not stat then
                vim.cmd([[echon ' ']])
                vim.notify("No such directory: " .. args[2], vim.log.levels.WARN)
            else
                if stat.type == "file" then
                    args[2] = vim.fs.dirname(args[2])
                end
                M.open_dir(args[2])
            end
        else
            vim.ui.input(
                { prompt = "Open directory: ", default = vim.uv.cwd(), completion = "dir"},
                function(pto)  -- pto = path to open
                    pto = vim.fn.fnamemodify(pto, ":p")
                    if pto == nil then
                        return
                    elseif pto == '' then
                        M.open_parent_dir()
                        return
                    end

                    local stat = vim.uv.fs_stat(pto)
                    if not stat then
                        vim.cmd([[echon ' ']])
                        vim.notify("No such directory: " .. pto, vim.log.levels.WARN)
                    else
                        if stat.type == "file" then
                            pto = vim.fs.dirname(pto)
                        end
                        M.open_dir(pto)
                    end
                end
            )
        end
        -- Open last simdir buffer
    elseif args[1] == M.commands[3] then
        M.open_last()
    -- Else unknow
    else
        vim.notify("[Simdir] Unknow command", vim.log.levels.ERROR)
    end
end

M.setup = function(user_opts)
    if user_opts ~= {} then M.config = user_opts
    else M.config = default_config end

    kmap.keymaps = M.config.keymaps

    core.init_hl_group()

    -- Create an autocommand group
    vim.api.nvim_create_augroup('Simdir_augroup', { clear = true })

    if M.config.default_file_explorer then
        vim.g.loaded_netrwPlugin = 1
        vim.g.loaded_netrw = 1

        if vim.fn.exists("#FileExplorer") then
            vim.api.nvim_create_augroup("FileExplorer", { clear = true })
        end

        -- Autocommand to open directories with Simdir
        vim.api.nvim_create_autocmd('VimEnter', {
            callback = function()
                local arg = vim.fn.argv(0)
                if arg ~= '' and vim.fn.isdirectory(arg) == 1 then
                    M.open_dir(vim.fn.fnamemodify(arg, ":p"))
                end
            end,
        })

        -- Autocommand to open directories with Simdir
        vim.api.nvim_create_autocmd('BufEnter', {
            callback = function()
                if vim.api.nvim_buf_get_name(0) == "simdir" then return end
                local path = vim.fn.expand('%:p')
                local stat = vim.loop.fs_stat(path)
                if stat and stat.type == 'directory' then
                    M.open_dir(path)
                end
            end,
        })
    end

    vim.api.nvim_create_user_command(
        'Simdir',
        function(opts)
            M.determine(opts)
        end,
        {
            nargs = 1,
            complete = function()
                return M.commands
            end,
        }
    )
end

return M
