add_requires("libssh")
add_requires("fmt")
add_requires("openssl")

if is_plat("macosx") then
    set_arch("x86_64")
end

local function plugin_bin_dir()
    local dir = "linux"
    if is_plat("windows") then
        dir = "win32"
    elseif is_plat("macosx") then
        local arch = get_config("arch")
        dir = arch == "arm64" and "mac-m1" or "mac-x86"
    end
    return path.join(os.projectdir(), "..", "..", "bin", dir)
end

local function sftp_pip()
    set_languages("cxx17")
    add_files(
        "src/sftp_pip.cc",
        "src/sftp_pip_impl.cc"
    )
    if is_plat("macosx") then
        set_arch("x86_64")
    end
    add_packages("libssh")
    add_packages("openssl")
    add_packages("fmt")
    after_build(function (target)
        local targetfile = target:targetfile()
        os.mkdir(plugin_bin_dir())
        os.cp(targetfile, plugin_bin_dir())
    end)
end

target("sftp_pip_d")
sftp_pip()

target("sftp_pip")
set_optimize("smallest")
add_ldflags("-s", {force = true})
set_symbols("none")
sftp_pip()
