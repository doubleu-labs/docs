# Bootstrap

This documentation goes through the process to stand-up the DoubleU Labs
Homelab.

I use Fedora Linux for my workstation, so any locally installed packages will
use `dnf`.

Each section is numbered to preserve the order they need to be performed in,
outside of section `00 - Rundown` which is purely informative regarding the
structure and plan of the Homelab.

## Software

### Required

```sh
sudo dnf install util-linux jq yubico-piv-tool yubikey-manager
```

- `wipefs`
- `fdisk`
- `jq`
- `yubico-piv-tool`
- `ykman`

CA Storage Specific:

Block storage:

```sh
sudo dnf install cryptsetup
```

- `cryptsetup`

KeePassXC Database:

```sh
sudo dnf install keepassxc
```

- `keepassxc-cli`

### Optional

```sh
sudo dnf install gdisk
```

- `sgdisk`