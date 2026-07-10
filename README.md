# nvim_ykm22_sftp

Neovim SFTP 上传/下载插件，可选对接 `nvim_ykm22_ui` 的 Git Changes。

## 依赖

- 必需：[`yakumo22-r/nvim-ykm22-ui`](https://github.com/yakumo22-r/nvim-ykm22-ui)
- 可选：`nvim-tree/nvim-tree.lua`（从文件树节点取路径）
- 系统：随插件附带的 `sftp_pip` 二进制

## 安装

### lazy.nvim

```lua
{
  "yakumo22-r/nvim-ykm22-ui",
  name = "nvim_ykm22_ui",
  lazy = false,
},
{
  "yakumo22-r/nvim-ykm22-sftp",
  name = "nvim_ykm22_sftp",
  lazy = false,
  dependencies = {
    "yakumo22-r/nvim-ykm22-ui",
  },
}
```

## 配置

```lua
require("nvim_ykm22_sftp").setup({
  -- 配置文件读取函数
  -- fun(name, default?, default_file?): content?, path?
  -- 插件会通过它读写 sftp_conf.lua
  read_file = function(name, default, default_file)
    -- 返回 content, abs_path
  end,

  -- 快捷键
  keymaps = {
    -- 打开 SFTP 浮动菜单，默认 "<leader>u"
    -- 设为 false 或 "" 可关闭
    sftp_menu = "<leader>u",
  },

  -- Git Changes 扩展
  git = {
    -- 是否向 nvim_ykm22_ui.git 注册 "Changes Upload"
    -- 默认 true
    enabled = true,
  },
})

-- 绑定项目根目录后才会解析配置并启动会话逻辑
require("nvim_ykm22_sftp").init(vim.fn.getcwd())
```

### 完整示例

```lua
local ProjectFile = require("ykm22.base.project-file") -- 你自己的项目配置模块

require("nvim_ykm22_ui.git").setup({
  read_file = ProjectFile.get_file,
  keymaps = {
    git_changes = "<C-g>",
  },
})

require("nvim_ykm22_sftp").setup({
  read_file = ProjectFile.get_file,
  keymaps = {
    sftp_menu = "<leader>u",
  },
  git = {
    enabled = true,
  },
})

-- 项目目录初始化后：
-- Sftp.init(project_root)
-- GitChangeView.init(project_root)
```

## 配置文件 `sftp_conf.lua`

首次可执行 `:SftpInitConf` 生成模板。

```lua
local confs = {}
local hosts = {}

local function host(tbl)
  table.insert(hosts, tbl)
  return tbl
end

local function conf(tbl)
  table.insert(confs, tbl)
  return tbl
end

local host1 = host {
  domain = "example.com",
  port = 22,
  username = "user",
  password = "password", -- 明文密码，请注意安全
}

conf {
  name = "example",
  host = host1,
  remoteRoot = "/remote/path",
  ignores = "node_modules, .git, .cache",
}

return {
  default = "example",
  confs = confs,
  hosts = hosts,
}
```

字段说明：

| 字段 | 说明 |
|------|------|
| `hosts[].domain` | 主机名 |
| `hosts[].port` | 端口，可选 |
| `hosts[].username` | 用户名，可选 |
| `hosts[].password` | 密码；为空时尝试公钥 |
| `confs[].name` | 配置名 |
| `confs[].host` | 关联 host 表 |
| `confs[].remoteRoot` | 远端根目录 |
| `confs[].ignores` | 忽略项（模板字段） |
| `default` | 默认配置名 |

## 命令

| 命令 | 说明 |
|------|------|
| `:SftpInitConf` | 初始化/重载 `sftp_conf.lua` |
| `:SftpEditConf` | 编辑当前配置文件 |
| `:SftpLs` | 列出配置 |
| `:SftpSwitch <name>` | 切换当前配置 |

## 快捷键

### 全局

| 键 | 说明 | 可配置 |
|----|------|--------|
| `<leader>u` | 打开 SFTP 浮动菜单 | `keymaps.sftp_menu` |

### SFTP 菜单内

| 键 | 说明 |
|----|------|
| `u` | 上传当前 buffer / 光标文件 |
| `U` | 选择配置后上传 |
| `s` | 从远端同步当前文件 |
| `S` | 选择配置后同步 |
| `c` | 上传 Git Changes 全部变更（在 Git 视图时） |
| `C` | 选择配置后上传 Git Changes |
| `m` | 切换 SFTP 配置 |
| `r` | 重载配置 |
| `L` | 打开日志窗口 |
| `R` | 退出 `sftp_pip` 进程 |
| `Enter` / `o` | 执行当前菜单项 |
| `q` / `Esc` | 关闭菜单 |

### Git Changes 扩展（`git.enabled = true`）

| 键 | 说明 |
|----|------|
| `u` | 在 Git Changes 视图中上传全部可上传变更 |

## API

```lua
local sftp = require("nvim_ykm22_sftp")

sftp.setup(opts)
sftp.init(root)

sftp.cmd_upload(conf, files)
sftp.cmd_sync(conf, files)
sftp.open_log()
sftp.exit_proc()

-- 兼容旧接口
sftp.get_confs()
sftp.get_curr_conf()
sftp.get_root()
```

## 二进制 `sftp_pip`

插件运行时从自身目录查找：

- Windows: `bin/win32/sftp_pip.exe`
- macOS x86: `bin/mac-x86/sftp_pip`
- macOS arm64: `bin/mac-m1/sftp_pip`
- Linux: `bin/linux/sftp_pip`

### 源码与构建

C++ 源码在 `native/sftp-pip`，依赖：

- libssh
- openssl
- fmt

构建：

```sh
cd native/sftp-pip
xmake
```

构建完成后会复制到 `bin/<platform>/`。

## 注意事项

1. `password` 明文保存在配置文件中，请勿提交到公共仓库。
2. 需要先 `init(root)`，否则上传路径和配置解析可能不正确。
3. `read_file` 由宿主配置提供；插件不强制绑定某种项目目录结构。
