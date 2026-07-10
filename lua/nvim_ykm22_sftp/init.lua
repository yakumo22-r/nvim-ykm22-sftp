--[[
    SFTP Module for Neovim
    This module provides functionality to manage SFTP connections, configurations, and file transfers.
    It includes commands to initialize configurations, edit them, list available configurations,
    switch between configurations, and perform file uploads and downloads.
--]]
local BufLog = require("nvim_ykm22_ui.buf_log")

---@class ykm22.nvim.Sftp
local M = {}

-- TAG: Config

---@type ykm22.nvim.SftpConf[]
local confs = nil
---@type table<string,ykm22.nvim.SftpConf>
local confMaps = {}
---@type ykm22.nvim.SftpConf
local curr = nil
---@type string
local _root = nil
---@type string
local confFile = nil

local scriptPath = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h")
local CommandsCreated = false

---@type fun(file:string,_, _):string?,string
local _readCfg = nil

---@param content string?
local function parseCfg(content)
    if not content then
        content, confFile = _readCfg("sftp_conf.lua")
    end

    if not content then
        -- vim.notify("Failed to read sftp_conf.lua. Please run :InitSftpConf", vim.log.levels.ERROR)
        return
    end
    local ok, err = load(content)
    if ok then
        local v = ok()
        confs = v.confs
        confMaps = {}
        for _, conf in ipairs(confs) do
            confMaps[conf.name] = conf
        end

        curr = confMaps[v.default] or v.confs[1]
        M.register_hosts(v.hosts)
    end
end

-- stylua: ignore start
function M.get_conf_file() return confFile end
function M.get_confs() return confs end
function M.get_curr_conf() return curr end
function M.get_root() return _root end
function M.get_conf_by_name(name) return name and confMaps[name] or nil end
-- stylua: ignore end


-- TAG: Response
local SFTP_PIP = require("nvim_ykm22_sftp.pip")
local ClientReady = false
local Starting = false
---@type fun()[]
local WaitReadyCmds = {}

---@param cmd fun()
function M.wait_client_ready(cmd)
    if not ClientReady then
        if not Starting then
            Starting = true
            SFTP_PIP.start(function()
                Starting = false
            end)
        end
        table.insert(WaitReadyCmds, cmd)
        return true
    end
end

---@class ykm22.nvim.SftpCallback
---@field cmd integer
---@field callback? fun(done:boolean, err?:boolean, msgs?:string[])
---@type table<integer, ykm22.nvim.SftpCallback>
local Callbacks = {}

local CMD_NEW_SESSION = 0
local CMD_UPLOADS = 1
local CMD_DOWNLOADS = 2
local CMD_CLOSE_SESSION = 3
local CMD_STATUS_SESSION = 4
local CMD_EXIT = 100

---@param id integer
---@param status integer
---@param msgs string[]
local function on_response(id, status, msgs) 
    if status == SFTP_PIP.RES_HELLO then
        ClientReady = true
        Starting = false
        for _, callback in ipairs(WaitReadyCmds) do
            callback()
        end
        if #msgs > 2 then
            for i=3,#msgs do
                M.log(SFTP_PIP.RES_HELLO, "Debug => ".. msgs[i])
            end
        else
            M.log(SFTP_PIP.RES_HELLO, "SFTP_PIP: Client is ready ".. (msgs[2] or "debug"))
        end
        WaitReadyCmds = {}
        return
    end

    local wait = Callbacks[id]
    if not wait then
        M.log(SFTP_PIP.RES_NVIM, "SFTP_PIP: No wait found for id: " .. tostring(id))
        return
    end

    for i=2,#msgs do
        M.log(status, msgs[i])
    end
    local done = status < 1
    local err = status == 2 or status < 0

    if wait.callback then
        wait.callback(done, err, msgs)
    end

    if done then
        Callbacks[id] = nil
    end
end

-- TAG: Request
---@class ykm22.nvim.SftpSession
---@field sessionId? integer
---@field user? string
---@field port? integer
---@field password? string
---@field queue function[]
---@field logging? boolean

---@type table<string,ykm22.nvim.SftpSession>
local SessionMap = {}

---@param msg string
local function on_process_exit(msg)
    Callbacks = {}
    -- SessionMap = {}
    ClientReady = false
    Starting = false
    for _, v in pairs(SessionMap) do
        v.queue = {}
        v.sessionId = nil
    end
    M.log(SFTP_PIP.RES_NVIM, msg)
end

local LOGStyle = {
    [SFTP_PIP.RES_HELLO] = BufLog.StyleYellow,
    [SFTP_PIP.RES_NVIM] = BufLog.StyleBlue,
    [SFTP_PIP.RES_INTERNAL_ERR] = BufLog.StyleRed,
    [SFTP_PIP.RES_ERROR] = BufLog.StyleRed,
    [SFTP_PIP.RES_ERROR_DONE] = BufLog.StyleRed,
    [SFTP_PIP.RES_DONE] = BufLog.StyleGreen,
    [SFTP_PIP.RES_NVIM_DONE] = BufLog.StyleGreen,
}

function M.open_log()
    if not M.logView:is_show() then
        M.logView:show()
    end
end

function M.exit_proc()
    M.log(SFTP_PIP.RES_NVIM, "SFTP_PIP: Exiting process")
    if ClientReady then
        local reqId = SFTP_PIP.raw_send(CMD_EXIT, 0, {"1"})
        Callbacks[reqId] = {
            cmd = CMD_EXIT,
            callback = function (done, err, msgs)
                ClientReady = false
                Starting = false
                -- reset
                for _,v in pairs(SessionMap) do
                    v.queue = {}
                    v.sessionId = nil
                end
                Callbacks = {}
            end
        }
    end
end

function M.log(status, info, err)
    local tag = SFTP_PIP.CBTag[status] or "[UNKNOWN]"
    local time = os.date("%H:%M:%S")
    local msg = string.format("%s %s %s", time, tag, info)
    vim.schedule(function()
        -- print(msg)
        M.logView:append(msg, LOGStyle[status])
        if not M.logView:is_show() then
            M.logView:show()
        end
    end)
    -- if not err then
    --     print()
    -- else
    --     vim.notify(string.format("%s %s %s", time, tag, info), vim.log.levels.ERROR)
    -- end
end

---@param hosts ykm22.nvim.SftpHost[]
function M.register_hosts(hosts)
    for _, host in ipairs(hosts) do
        local s = SessionMap[host.domain] or {}
        if s.sessionId and (
            s.user ~= host.username or
            s.port ~= host.port or
            s.password ~= host.password
        ) then
            M.close_session(s.sessionId)
            s.sessionId = nil
        end
        SessionMap[host.domain] = s
        s.user = host.username
        s.port = host.port
        s.password = host.password
        s.queue = {}
        s.logging = false
    end
end

---@param hostname string
---@param cmd fun()
function M.wait_login(hostname, cmd)
    local info = SessionMap[hostname]
    if not info then
        M.log(SFTP_PIP.RES_NVIM, "SFTP_PIP: No session found for hostname: " .. tostring(hostname), true)
        return true
    end

    if not info.sessionId then
        table.insert(info.queue, cmd)
        if not info.logging then
            M.login(hostname)
        end
        return true
    end
end

---@param hostname string
function M.login(hostname)
    local info = SessionMap[hostname]
    local user = info.user or "#"
    local port = info.port or "#"
    local password = info.password or "#"
    info.logging = true

    if M.wait_client_ready(function()
        M.login(hostname)
    end) then
        return
    end

    local reqId = SFTP_PIP.raw_send(CMD_NEW_SESSION, 0, {
        hostname,
        user,
        password,
        tostring(port),
    })

    Callbacks[reqId] = {
        cmd = CMD_NEW_SESSION,
        callback = function(done, err, msgs)
            if not err and done then
                info.sessionId = tonumber(msgs[2])
                info.logging = false
                -- print("login success: " .. hostname, #info.queue)
                for _,cmd in ipairs(info.queue) do
                    cmd()
                end
                info.queue = {}
            end
        end,
    }
end

function M.close_session(sessionId)
    local reqId = SFTP_PIP.raw_send(CMD_CLOSE_SESSION, sessionId, {"1"})
    Callbacks[reqId] = { cmd = CMD_CLOSE_SESSION }
end

---@param hostname string
---@param localRoot string
---@param remoteRoot string
---@param files string[]
function M.upload_files(hostname, localRoot, remoteRoot, files, cfg_name)

    if M.wait_login(hostname, function()
        M.upload_files(hostname, localRoot, remoteRoot, files, cfg_name)
    end) then
        return
    end

    local info = SessionMap[hostname]
    local reqId = SFTP_PIP.raw_send(CMD_UPLOADS, info.sessionId, {
        localRoot,
        remoteRoot,
        table.concat(files, "\n"),
    })

    Callbacks[reqId] = { cmd = CMD_UPLOADS,
        callback = cfg_name and function (done, err, msgs)
            if not err and done then
                M.log(SFTP_PIP.RES_NVIM_DONE, string.format("<<<<<<<< %s upload done", cfg_name))
            end
        end
    }
end

---@param hostname string
---@param localRoot string
---@param remoteRoot string
---@param files string[]
function M.dowload_files(hostname, localRoot, remoteRoot, files)
    local info = SessionMap[hostname]

    if M.wait_login(hostname, function()
        M.dowload_files(hostname, localRoot, remoteRoot, files)
    end) then
        return
    end


    local reqId = SFTP_PIP.raw_send(CMD_DOWNLOADS, info.sessionId, {
        localRoot,
        remoteRoot,
        table.concat(files, "\n"),
    })

    Callbacks[reqId] = { cmd = CMD_DOWNLOADS }
end

function M.check_not_ready()
    if confs == nil then
        vim.notify("SFTP: No configuration found. Please run :SftpInitConf", vim.log.levels.ERROR)
        return true
    end
end

function M.cmd_init_sftp_conf()
    local content
    content,confFile = _readCfg("sftp_conf.lua", nil, scriptPath .. "/conf_temp/sftp_conf.lua")
    if not content then
        vim.notify("Failed to init sftp_conf", vim.log.levels.ERROR)
    end
    parseCfg(content)
end

function M.cmd_edit_sftp_conf()
    if M.check_not_ready() then return end
    vim.cmd("edit " .. confFile)
end

function M.cmd_list_conf()
    if M.check_not_ready() then return end
    print("SFTP list")
    for _, conf in ipairs(confs) do
        print(string.format("%s - host: %s, remote: %s", conf.name, conf.host.domain, conf.remoteRoot))
    end
end

function M.cmd_switch_conf(opts, name)
    if M.check_not_ready() then return end
    local v = opts and tostring(opts.args) or name
    if confMaps[v] then
        curr = confMaps[v]
    else
        vim.notify("SFTP: No configuration found for " .. v, vim.log.levels.ERROR)
        return
    end
end

local function create_commands()
    if CommandsCreated then
        return
    end
    CommandsCreated = true
    vim.api.nvim_create_user_command("SftpInitConf", M.cmd_init_sftp_conf, {})
    vim.api.nvim_create_user_command("SftpEditConf", M.cmd_edit_sftp_conf, {})
    vim.api.nvim_create_user_command("SftpLs", M.cmd_list_conf, {})
    vim.api.nvim_create_user_command("SftpSwitch", M.cmd_switch_conf, {
        nargs = 1,
        complete = function(_, _)
            return vim.tbl_keys(confMaps)
        end,
    })
end

---@param conf ykm22.nvim.SftpConf
function M.cmd_upload(conf,files)
    conf = conf or curr
    if files then
        M.upload_files( --
            conf.host.domain,
            M.get_root(),
            conf.remoteRoot,
            files,
            conf.name
        )
    else
        vim.notify("No valid file to upload", vim.log.levels.ERROR)
    end
end

function M.cmd_sync(conf,files)
    conf = conf or curr
    if files then
        M.dowload_files( --
            conf.host.domain,
            M.get_root(),
            conf.remoteRoot,
            files
        )
    else
        vim.notify("No valid file to sync", vim.log.levels.ERROR)
    end
end

---@param readCfg fun(file:string,_, _):string?,string
function M.setup(readCfg)
    local opts = type(readCfg) == "table" and readCfg or nil
    _readCfg = opts and opts.read_file or readCfg

    M.view = require("nvim_ykm22_sftp.view")
    M.view.setup(M)
    create_commands()

    local git_enabled = not (opts and opts.git and opts.git.enabled == false)
    if git_enabled then
        local ok, git = pcall(require, "nvim_ykm22_ui.git")
        if ok and git.register_actions then
            git.register_actions({
                {
                    name = "Changes Upload",
                    key = "u",
                    callback = function(ctx)
                        M.cmd_upload(nil, ctx and ctx.files)
                    end,
                },
            })
        end
    end
end

---@param root string
function M.init(root)
    M.logView = BufLog.new()
    _root = root
    parseCfg()
    SFTP_PIP.register_callbacks({
        on_response = on_response,
        on_process_exit = on_process_exit,
        sftp_log = M.log,
    })

    create_commands()
end

return M
