# OOBM Service Node

We'll use a Raspberry Pi running Fedora CoreOS for this. The only software
running will be a `dnsmasq` container serving DNS, DHCP, and TFTP. This will
assign IP addresses to all devices on the OOBM network, which will allow us to
pull the configuration files from the TFTP server for the switches.

!!! note
    We're pulling the script manually on the PowerConnect 6248 instead of using
    DHCP options to automatically provision the switch. This is because I could
    not figure out how to get the `AutoInstall` service working. No matter the
    complexity or file-format (CRLF vs LF) of the file, the `AutoInstall`
    service would fail and report that the configuration file was
    "inconsistent", offering no additional debugging information.

    The PowerSwitch S4810's Bare-Metal Provisioning (BMP) system functions
    transparently, so _that_ switch will use DHCP-provided configuration files
    to automatically set itself up.

    At some point, this ancient switch needs to go...

The iDRACs and other management interfaces will also receive their connection
parameters through this same DHCP server.

## Generate Butane and Ignition

First, we need to generate a usable Butane configuration file that will be
transpiled into an Ignition file. We'll use `yq` to insert your SSH public key
into the list of authorized keys.

```sh
export COREUSER='.passwd.users[select(.name == "core")]'
```

```sh
PUBKEY=$(cat $HOME/.ssh/id_ed25519.pub) \
yq 'eval(strenv(COREUSER)).ssh_authorized_keys += [strenv(PUBKEY)]' \
$LABBOOTSTRAPPATH/fcos/oobm-srv/butane.bu.tpl \
> $LABBOOTSTRAPPATH/fcos/oobm-srv/butane.bu
```

If you have additional SSH public keys to add, use the following to include
them:

```sh
PUBKEY=$($HOME/.ssh/id_rsa.pub) \
yq -i 'eval(strenv(COREUSER)).ssh_authorized_keys += strenv(PUBKEY)' \
$LABBOOTSTRAPPATH/fcos/oobm-srv/butane.bu
```

If you want to add a password:

```sh
PASSWD=$(mkpasswd -m yescrypt) \
yq -i 'eval(strenv(COREUSER)).password_hash = strenv(PASSWD)' \
$LABBOOTSTRAPPATH/fcos/oobm-srv/butane.bu
```

After any additional changes you wish are made to the Butane file, transpile it
using the `butane` command and write the output to the Ignition file:

```sh
butane -d $LABBOOTSTRAPPATH \
< $LABBOOTSTRAPPATH/fcos/oobm-srv/butane.bu \
> $LABBOOTSTRAPPATH/fcos/oobm-srv/ignition.ign
```

## Stage U-Boot

Now we need to unpack the U-Boot RPMs into a working directory that can be
coppied to the `EFI-SYSTEM` partition once `coreos-installer` writes the OS to
the SD card.

```sh
for f in $LABBOOTSTRAPPATH/raspberry-pi/uboot/rpm/*.rpm; do
    rpm2cpio $f | cpio -idv -D $LABBOOTSTRAPPATH/raspberry-pi/uboot/root
done
```

Move the Raspberry Pi `u-boot.bin` binary to the `boot/efi` directory:

```sh
mv $LABBOOTSTRAPPATH/raspberry-pi/uboot/root/usr/share/uboot/rpi_arm64/u-boot.bin \
$LABBOOTSTRAPPATH/raspberry-pi/uboot/root/boot/efi/rpi-u-boot.bin
```

Next, we can append some parameters to the Raspberry Pi `config.txt` file in the
staged `boot/efi` directory:

```sh
cat $LABBOOTSTRAPPATH/raspberry-pi/partial.config.txt \
>> $LABBOOTSTRAPPATH/raspberry-pi/uboot/root/boot/efi/config.txt
```

!!! note
    Here we enabled the DS3231 RTC, and disabled Bluetooth and WiFi. Adjust this
    to suite your needs.

## Flash Image

Insert the SD card into a reader and write Fedora CoreOS to it:

```sh
sudo coreos-installer install --offline \
-f $LABBOOTSTRAPPATH/fcos/fedora-coreos-*-metal.aarch64.raw.xz \
-i $LABBOOTSTRAPPATH/fcos/oobm-srv/ignition.ign \
/dev/mmcblk0
```

Get the device ID of the `EFI-SYSTEM` partition and mount it using `udiskctl`:

```sh
EFIPART=$(lsblk -Q 'LABEL == "EFI-SYSTEM"' -no PATH /dev/mmcblk0)
```

```sh
udiskctl mount -b $EFIPART
```

Use `rsync` to copy the U-Boot files to the boot partition:

```sh
rsync -avh --ignore-existing \
$LABBOOTSTRAPPATH/raspberry-pi/uboot/root/boot/efi/ \
/run/media/$USER/EFI-SYSTEM/
```

Unmount the partition:

```sh
udiskctl unmount -b $EFIPART
```

## Create Archive Partition

```sh
sudo sgdisk /dev/mmcblk0 -e
```

```sh
sudo sgdisk /dev/mmcblk0 -n 5:-500M: -t 5:8300 -c 5:ARCHIVE
```

```sh
sudo mkfs.vfat -F32 -nARCHIVE /dev/mmcblk0p5
```

```sh
udiskctl mount -b /dev/mmcblk0p5
```

```sh
cp $LABBOOTSTRAPPATH/fcos/oobm-srv/dnsmasq.tar /run/media/$USER/ARCHIVE/
```

```sh
udiskctl unmount -b /dev/mmcblk0p5
```

## Boot OOBM-SRV Node

Insert the SD card into the Raspberry Pi and boot it. When the Ignition process
completes, the dnsmasq container should automatically start and begin handing
out IP addresses.