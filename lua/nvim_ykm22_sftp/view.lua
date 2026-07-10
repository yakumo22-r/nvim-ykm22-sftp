local V = require("nvim_ykm22_ui.view")
local fs = require("nvim_ykm22_ui.fs")
local floatMenu = require("nvim_ykm22_ui.float_menu").new()
floatMenu.Width = 30
floatMenu.BufWidth = 30

---@type ykm22.nvim.Sftp
local Handle = nil
local GitChangeView = nil

---@class ykm22.nvim.SftpView
local M = {}

if not ykm22 then ykm22 = {} end

---@class ykm22.nvim.SftpViewConfig

-- TODO:
---@param files string[]
function M.take_group_by_git(files) end


---@return any
local function NvimTreeApi()
    local ok, api = pcall(require, "nvim-tree.api")

    if ok then
        return api
    end
end

---@return string[]|nil
local function get_relative_files_on_buf(buf)
    local bufname = vim.api.nvim_buf_get_name(buf)
    local buftype = vim.bo[buf].buftype
    local path
    local isdir = false
    if buftype == "" then
        path = bufname
    elseif buftype == "nofile" then
        local api = NvimTreeApi()
        bufname = vim.fn.fnamemodify(bufname, ":p")
        if api and bufname:match("NvimTree_") then
            local node = api.tree.get_node_under_cursor()
            isdir = node.type == "directory"
            path = node.absolute_path
        elseif GitChangeView and GitChangeView.get_buf() == buf then
            local files = GitChangeView.get_cursor_abs_paths(Handle.get_root())
            if files[1] then
                return files
            end
        end
    end

    if isdir then
        local files = fs.get_all_subfiles(path, Handle.get_root())
        if #files > 0 then
            return files
        end
    elseif path then
        return { vim.fs.relpath(Handle.get_root(), path) }
    end
end

local Menu = {}
---@param text string
---@return ykm22.nvim.FloatMenuELement
function Menu.title(text)
    return {
        label = { V.style_cell(V.center_text(text, floatMenu.Width, "━"), 0, V.StyleInfo) },
    }
end

local function style_key(k)
    return V.style_cell(" "..k, 0, V.StyleHint)
end

---@return ykm22.nvim.FloatMenuELement
function Menu.switchConf()
    local currConf = Handle.get_curr_conf()

    local cell = style_key("m")
    local cell2 = V.style_cell(string.format(" Switch(%s)", currConf.name))
    local cell3 = V.style_cell(V.right_text(" > ", floatMenu.Width - cell.width - cell2.width), 0, V.StyleOk)
    return {
        label = { cell, cell2, cell3 },
        action = function()
            floatMenu:set_list(Menu.confSelects("Switch Config", Handle.cmd_switch_conf))
            floatMenu:show()
            return false
        end,
        key = "m",
    }
end

function Menu.testBtn()
    local width = floatMenu.Width
    local cell = V.style_cell(" testBtn")
    local cell2 = V.style_cell(V.right_text(" > ", width - cell.width), 0, V.StyleError)

    ---@type ykm22.nvim.FloatMenuELement
    return {
        label = { cell, cell2 },
        action = function(v)
            return true
        end,
    }
end

function Menu.edit_config()
    return {
        label = " Edit Config",
        action = function()
            vim.schedule(Handle.cmd_edit_sftp_conf)
            return true
        end,
    }
end

function Menu.reload_config()
    ---@type ykm22.nvim.FloatMenuELement
    return {
        label = { style_key("r"), V.style_cell(" Reload Config") },
        action = function()
            Handle.cmd_init_sftp_conf()
            return true
        end,
        key = "r",
    }
end

function Menu.open_log()
    ---@type ykm22.nvim.FloatMenuELement
    return {
        label = { style_key("L"), V.style_cell(" Open Log") },
        action = function()
            Handle.open_log()
            return true
        end,
        key = "L",
    }
end

function Menu.exit_proc()
    ---@type ykm22.nvim.FloatMenuELement
    return {
        label = { style_key("R"), V.style_cell(" Quit SFTP_PIP") },
        action = function()
            Handle.exit_proc()
            return true
        end,
        key = "R",
    }
end

function Menu.git_changes_upload()
    ---@type ykm22.nvim.FloatMenuELement
    return {
    label = { style_key("c"), V.style_cell(" Changes Upload ") },
    action = function(v)
        local files = GitChangeView.get_need_upload_files(Handle.get_root())
        -- print(vim.inspect(files))
        Handle.cmd_upload(nil, files)
        return true
    end,
    key = "c"
}
end


function Menu.git_changes_upload_to()
    local cell = style_key("C")
    local cell2 = V.style_cell(" Changes Upload to")
    local cell3 = V.style_cell(V.right_text(" > ", floatMenu.Width - cell.width - cell2.width), 0, V.StyleOk)
    ---@type ykm22.nvim.FloatMenuELement
    return {
        label = { cell, cell2 , cell3 },
        action = function(v)
            
            local files = GitChangeView.get_need_upload_files(Handle.get_root())
            local lists = Menu.confSelects("Changes Upload to", function(_, name)
                if not name or name == "" then
                    return
                end
                local conf = Handle.get_conf_by_name(name)
                if not conf then
                    vim.notify("No such configuration: " .. name, vim.log.levels.ERROR)
                    return
                end
                Handle.cmd_upload(conf, files)
            end)
            floatMenu:set_list(lists)
            floatMenu:show()
        end,
        key = "C",
    }

end

function Menu.upload()
    ---@type ykm22.nvim.FloatMenuELement
    return {
        label = { style_key("u"), V.style_cell(" Upload ")  },
        action = function(v)
            local files = get_relative_files_on_buf(v.lastBuf)
            Handle.cmd_upload(nil, files)
            return true
        end,
        key = "u",
    }
end


function Menu.upload_to()
    local cell = style_key("U")
    local cell2 = V.style_cell(" Upload to")
    local cell3 = V.style_cell(V.right_text(" > ", floatMenu.Width - cell.width - cell2.width), 0, V.StyleOk)
    ---@type ykm22.nvim.FloatMenuELement
    return {
        label = { cell, cell2 , cell3 },
        action = function(v)
            local files = get_relative_files_on_buf(v.lastBuf)
            local lists = Menu.confSelects("Upload to", function(_, name)
                if not name or name == "" then
                    return
                end
                local conf = Handle.get_conf_by_name(name)
                if not conf then
                    vim.notify("No such configuration: " .. name, vim.log.levels.ERROR)
                    return
                end
                Handle.cmd_upload(conf, files)
            end)
            floatMenu:set_list(lists)
            floatMenu:show()
        end,
        key = "U",
    }
end

function Menu.sync()
    ---@type ykm22.nvim.FloatMenuELement
    return {
        label = { style_key("s"), V.style_cell(" Sync ") },
        action = function(v)
            local files = get_relative_files_on_buf(v.lastBuf)
            Handle.cmd_sync(nil, files)
            return true
        end,
        key = "s",
    }
end

function Menu.sync_from() 
    local cell = style_key("S")
    local cell2 = V.style_cell(" Sync from")
    local cell3 = V.style_cell(V.right_text(" > ", floatMenu.Width - cell.width - cell2.width), 0, V.StyleOk)
    return {
        label = { cell, cell2, cell3 },
        action = function(v)
            local files = get_relative_files_on_buf(v.lastBuf)
            local lists = Menu.confSelects("Upload to", function(_, name)
                if not name or name == "" then
                    return
                end
                local conf = Handle.get_conf_by_name(name)
                if not conf then
                    vim.notify("No such configuration: " .. name, vim.log.levels.ERROR)
                    return
                end
                Handle.cmd_sync(conf, files)
            end)
            floatMenu:set_list(lists)
            floatMenu:show()
        end,
        key = "S",
    }
end

---@param title string
---@param e fun(_,name:string)
---@return ykm22.nvim.FloatMenuELement[]
function Menu.confSelects(title, e)
    local confs = Handle.get_confs()
    local currConf = Handle.get_curr_conf()

    local eles = { Menu.title(title) }
    for _, conf in ipairs(confs) do
        local text
        if conf.name == currConf.name then
            text = string.format("(*) %s", conf.name)
            text = { V.style_cell(text, 0, V.StyleOk) }
        else
            text = string.format("%s", conf.name)
        end

        table.insert(eles, {
            label = text,
            action = function()
                if currConf.name ~= conf.name then
                    e(nil, conf.name)
                end
                return true
            end,
        })
    end

    return eles
end

function M.show_float_ops()
    ---@type ykm22.nvim.FloatMenuELement[]
    local menus = {
        Menu.title(" SFTP Menu "),
    }

    floatMenu.MinusRange[1] = 1
    if not Handle.get_curr_conf() then
        table.insert(menus, {
            label = V.center_text(" SftpInitConf", floatMenu.Width),
            action = function()
                Handle.cmd_init_sftp_conf()
                return true
            end,
        })
    else

        local isGrp = false
        if GitChangeView and vim.api.nvim_get_current_buf() == GitChangeView.get_buf() then
            table.insert(menus, Menu.git_changes_upload())
            table.insert(menus, Menu.git_changes_upload_to())
            if not GitChangeView.get_cursor_abs_paths()[1] then
                isGrp = true
                if not GitChangeView.get_need_upload_files(Handle.get_root())[1] then
                    return
                end
            end
        end

        if not isGrp then
            table.insert(menus, Menu.upload())
            table.insert(menus, Menu.sync())
            table.insert(menus, Menu.upload_to())
            table.insert(menus, Menu.sync_from())
        end
        table.insert(menus, Menu.switchConf())
        table.insert(menus, Menu.reload_config())
        table.insert(menus, Menu.open_log())
        table.insert(menus, Menu.exit_proc())
    end

    floatMenu:set_list(menus)
    floatMenu:show()
end

---@param handle ykm22.nvim.Sftp
function M.setup(handle)
    Handle = handle
    local ok, git = pcall(require, "nvim_ykm22_ui.git")
    if ok then
        GitChangeView = git
    end
    vim.keymap.set("n", "<leader>u", M.show_float_ops, { noremap = true, silent = true })
end

return M
