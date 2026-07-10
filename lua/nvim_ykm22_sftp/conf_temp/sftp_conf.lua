-- base sftp configuration

---@return ykm22.nvim.SftpConf[]
local confs = {}

---@return ykm22.nvim.SftpHost[]
local hosts = {}

-- stylua: ignore start
---@param tbl ykm22.nvim.SftpHost
local function host(tbl) 
    table.insert(hosts, tbl)
    return tbl 
end

---@param tbl ykm22.nvim.SftpConf
local function conf(tbl) 
    table.insert(confs, tbl)
    return tbl 
end
-- stylua: ignore end

local host1 = host {
    domain = "example.com",
    port = 22,
    username = "user",
    password = "password",
}

conf {
    name = "example",
    host = host1,
    remoteRoot = "/remote/path",
    ignores = "node_modules, .git, .cache",
}


return {
    default = "example",
    ---@return ykm22.nvim.SftpConf[]
    confs = confs,
    hosts = hosts,

}

---@class ykm22.nvim.SftpHost
---@field domain string
---@field port? number
---@field username? string
---@field password? string

---@class ykm22.nvim.SftpConf
---@field name string
---@field host ykm22.nvim.SftpHost
---@field remoteRoot string
---@field ignores string
