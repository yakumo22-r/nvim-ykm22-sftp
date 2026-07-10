# nvim_ykm22_sftp

SFTP support for Neovim.

## Native helper

The `sftp_pip` helper source is kept in `native/sftp-pip`.

Build with xmake:

```sh
cd native/sftp-pip
xmake
```

After build, `xmake.lua` copies the executable into the plugin runtime bin directory:

- Windows: `bin/win32/sftp_pip.exe`
- macOS x86: `bin/mac-x86/sftp_pip`
- macOS arm64: `bin/mac-m1/sftp_pip`
- Linux: `bin/linux/sftp_pip`
