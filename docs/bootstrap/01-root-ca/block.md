# CA Secrets - Block Storage

!!! note
    The following commands are required in your `PATH`:

    - `cryptsetup`
    - `wipefs`

    The following commands are optional:

    - `sgdisk`

This storage method will provision a block device (eg. USB drive) for storing
Root CA data and secrets. Secrets will be located in LUKS-encrypted partitions.
**This means that CA operations can only be performed on Linux-based systems.**

The plan is to create three minimum-sized LUKS-encrypted exFAT partitions, a
first for YubiKey secrets (Management Key, PIN, and PIN Unlock Key (PUK)), a
second for backing up the Root CA and Github App private keys, and a third for
storing only a file containing the YubiKey PIV PIN.

The separate partition for the PIN is so that only the file containing the PIN
is exposed to the system when performing CA operations instead of all secrets.

This example uses a 32GB USB flash drive.

Store the device path of the drive in an environment variable.

```sh
export DEVICE="/dev/sdb"
```

## Wipe Device

Use `wipefs` to wipe any partitions, then use it again to wipe the base device:

```sh
sudo wipefs -af $DEVICE*
```

```sh
sudo wipefs -af $DEVICE
```

## Create Partitions

!!! note
    If you have `sgdisk` available, formatting can be accomplished with the
    following one-liner:

    ```sh
    sudo sgdisk \
    -n 1::+64M -t 1:8309 -c 1:YUBISEC \
    -n 2::+64M -t 2:8309 -c 2:ROOTCASEC \
    -n 3::+64M -t 3:8309 -c 3:YKPIN \
    -n 4::0 -t 4:0700 -c 4:CADATA \
    $DEVICE
    ```

    If you do, you can skip to [Encrypt Partitions](#encrypt-partitions)

Format the drive using `fdisk`:

```sh
sudo fdisk $DEVICE
```

Create a new GPT partition table:

```{.sh .no-copy}
Command (m for help): g
Created a new GPT disklabel (GUID: DE322DEF-9163-4001-AE49-70973332FFEC).
```

Create the first partition and set the partition type GUID code to `Linux LUKS`:

```txt title="Linux LUKS Partition type GUID"
CA7D7CCB-63ED-4C53-861C-1742536059CC
```

```{.sh .no-copy}
Command (m for help): n
Partition number (1-128, default 1): 
First sector (2048-60088286, default 2048): 
Last sector, +/-sectors or +/-size{K,M,G,T,P} (2048-60088286, default 60086271): +64M
Created a new partition 1 of type 'Linux filesystem' and of size 64 MiB.

Command (m for help): t
Selected partition 1
Partition type or alias (type L to list all): CA7D7CCB-63ED-4C53-861C-1742536059CC
Changed type of partition 'Linux filesystem' to 'unknown'.
```

Now repeat this for the next two partitions:

```{.sh .no-copy}
Command (m for help): n
Partition number (2-128, default 2): 
First sector (133120-60088286, default 133120): 
Last sector, +/-sectors or +/-size{K,M,G,T,P} (133120-60088286, default 60086271): +64M
Created a new partition 2 of type 'Linux filesystem' and of size 64 MiB.

Command (m for help): t
Partition number (1,2, default 2): 
Partition type or alias (type L to list all): CA7D7CCB-63ED-4C53-861C-1742536059CC
Changed type of partition 'Linux filesystem' to 'unknown'.
```

```{.sh .no-copy}
Command (m for help): n
Partition number (3-128, default 3): 
First sector (264192-60088286, default 264192): 
Last sector, +/-sectors or +/-size{K,M,G,T,P} (264192-60088286, default 60086271): +64M
Created a new partition 3 of type 'Linux filesystem' and of size 64 MiB.

Command (m for help): t
Partition number (1-3, default 3): 
Partition type or alias (type L to list all): CA7D7CCB-63ED-4C53-861C-1742536059CC
Changed type of partition 'Linux filesystem' to 'unknown'.
```

Create the final partition using the remaining space on the device. Set the
partition type GUID to `Microsoft basic data`:

```txt title="Microsoft basic data partition type GUID"
EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
```

```{.sh .no-copy}
Command (m for help): n
Partition number (4-128, default 4): 
First sector (395264-60088286, default 395264): 
Last sector, +/-sectors or +/-size{K,M,G,T,P} (395264-60088286, default 60086271):
Created a new partition 4 of type 'Linux filesystem' and of size 28.5 GiB.

Command (m for help): t
Partition number (1-4, default 4): 
Partition type or alias (type L to list all): EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
Changed type of partition 'Linux filesystem' to 'Microsoft basic data'.
```

Write the partition table:

```{.sh .no-copy}
Command (m for help): w
The partition table has been altered.
Calling ioctl() to re-read partition table.
Syncing disks.
```

## Encrypt Partitions

Use `cryptsetup` to encrypt the first three partitions:

```sh
sudo cryptsetup -q luksFormat --label YUBISEC ${DEVICE}1
Enter passphrase for /dev/sdb1: 
```

```sh
sudo cryptsetup -q luksFormat --label ROOTCASEC ${DEVICE}2
Enter passphrase for /dev/sdb2: 
```

```sh
sudo cryptsetup -q luksFormat --label YKPIN ${DEVICE}3
Enter passphrase for /dev/sdb3: 
```

## Format Encrypted Partitions

For each encrypted partition, get the `luksUUID` for each partition, unlock it
by UUID, format it using `mkfs.exfat`, then close it:

```sh
LUKS_UUID=$(sudo cryptsetup luksUUID ${DEVICE}1)

sudo cryptsetup open ${DEVICE}1 "luks-${LUKS_UUID}"

sudo mkfs.exfat -L YUBISEC "/dev/mapper/luks-${LUKS_UUID}"

sudo cryptsetup close "luks-${LUKS_UUID}"
```

```sh
LUKS_UUID=$(sudo cryptsetup luksUUID ${DEVICE}2)

sudo cryptsetup open ${DEVICE}2 "luks-${LUKS_UUID}"

sudo mkfs.exfat -L ROOTCASEC "/dev/mapper/luks-${LUKS_UUID}"

sudo cryptsetup close "luks-${LUKS_UUID}"
```

```sh
LUKS_UUID=$(sudo cryptsetup luksUUID ${DEVICE}3)

sudo cryptsetup open ${DEVICE}3 "luks-${LUKS_UUID}"

sudo mkfs.exfat -L YKPIN "/dev/mapper/luks-${LUKS_UUID}"

sudo cryptsetup close "luks-${LUKS_UUID}"
```

## Format Data Partition

Finally, format the large remaining partition. This will be used to hold the
OpenSSL CA file structure.

```sh
sudo mkfs.exfat -L CADATA ${DEVICE}4
```
