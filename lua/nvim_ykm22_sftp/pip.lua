---@type any
local uv = vim.uv

local M = {}
local id = 0

---@type table|nil
local cb

local function plugin_root()
    local source = debug.getinfo(1, "S").source:sub(2)
    return vim.fn.fnamemodify(source, ":p:h:h:h")
end

local function local_exec(exec)
    local dir = "linux"
    local suffix = ""
    if vim.fn.has("win32") == 1 then
        dir = "win32"
        suffix = ".exe"
    elseif vim.fn.has("mac") == 1 then
        local arch = vim.fn.system("uname -m"):gsub("%s+", "")
        dir = arch == "arm64" and "mac-m1" or "mac-x86"
    end
    return string.format("%s/bin/%s/%s%s", plugin_root(), dir, exec, suffix)
end

function M.register_callbacks(_cb)
    cb = _cb
end

function M.start(callback)
    M.stdout = uv.new_pipe(false)
    M.stderr = uv.new_pipe(false)
    M.stdin = uv.new_pipe(false)

    M.handle = uv.spawn(local_exec("sftp_pip"), {
        stdio = { M.stdin, M.stdout, M.stderr },
    }, function(code, signal)
        M.stop()
        cb.on_process_exit("exec SFTP_PIP exited with code (" .. tostring(code) .. ") and signal -> " .. tostring(signal))
    end)

    if not M.handle then
        callback()
        cb.sftp_log(M.RES_INTERNAL_ERR, "Failed to exec SFTP_PIP")
        return
    end

    M.cache = {}

    M.stdout:read_start(function(err, data)
        if err then
            cb.sftp_log(M.RES_NVIM, "SFTP_PIP stdout error: " .. err, true)
        elseif data then
            local lines = vim.split(data, "\n", { trimempty = false })
            for _, line in ipairs(lines) do
                if vim.trim(line) == "" then
                    if M.cache[1] then
                        M.decode_res(M.cache)
                    end
                    M.cache = {}
                else
                    table.insert(M.cache, line)
                end
            end
        end
    end)

    M.stderr:read_start(function(err, data)
        if err then
            cb.sftp_log(M.RES_NVIM, "SFTP_PIP stderr error: " .. err, true)
            return
        end
        if data then
            cb.sftp_log(M.RES_NVIM, "SFTP_PIP Subprocess error: " .. data, true)
        end
    end)
end

M.RES_INTERNAL_ERR = -2
M.RES_ERROR_DONE = -1
M.RES_DONE = 0
M.RES_INFO = 1
M.RES_ERROR = 2
M.RES_HELLO = 99
M.RES_NVIM = 100
M.RES_NVIM_DONE = 101

M.CBTag = {
    [M.RES_INTERNAL_ERR] = "[INTERNAL_ERR]",
    [M.RES_ERROR_DONE] = "[ERROR_DONE]",
    [M.RES_DONE] = "[SUCCESS_DONE]",
    [M.RES_INFO] = "[INFO]",
    [M.RES_ERROR] = "[ERROR]",
    [M.RES_HELLO] = "[HELLO WORLD]",
    [M.RES_NVIM] = "[NVIM]",
    [M.RES_NVIM_DONE] = "[NVIM_DONE]",
}

---@param msgs string[]
function M.decode_res(msgs)
    local _, b, c = msgs[1]:match("(%d+)%s+(%d+)%s+(%d+)")
    local _id = tonumber(b) or -1
    local status = tonumber(c) or 1
    cb.on_response(_id, status, msgs)
end

---@param cmd integer
---@param sessionId integer
---@param msgs string[]
function M.raw_send(cmd, sessionId, msgs)
    local _id = id
    id = id + 1
    local head = table.concat({ cmd, _id, sessionId }, " ")
    for i, msg in ipairs(msgs) do
        if msg == "" then
            msgs[i] = "#"
        end
    end
    table.insert(msgs, "")
    local msg = head .. "\n" .. table.concat(msgs, "\n") .. "\n"

    M.stdin:write(msg, function(err)
        if err then
            cb.sftp_log(M.RES_NVIM, "SFTP_PIP write error: " .. err, true)
            cb.on_response(_id, M.RES_INTERNAL_ERR, { "", "SFTP_PIP write error: " .. err })
            M.stop()
        end
    end)

    return _id
end

function M.running()
    return M.handle ~= nil
end

function M.stop()
    if M.handle then
        id = 0
        M.handle:kill(15)
        M.stdout:read_stop()
        M.stderr:read_stop()
        M.stdin:close()
        M.stdout:close()
        M.stderr:close()
        M.handle:close()
        M.handle = nil
    end
end

return M
