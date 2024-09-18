# CA Secrets - KeePassXC Database Storage

!!! note
    The following commands are required in your `PATH`:

    - `keepassxc-cli`
    - `wipefs`

    The following commands are optional:

    - `sgdisk`

!!! note
    If you're using the KeePassXC AppImage, you'll need to make the AppImage
    executable and create an alias for the CLI. Make sure the path to the
    AppImage is absolute.

    ```sh
    chmod +x ~/Downloads/KeePassXC-*.AppImage
    ```

    ```sh
    alias keepassxc-cli="~/Downloads/KeePassXC-*.AppImage cli"
    ```

This storage method will use KeePassXC databases to store secrets. This method
is more flexible than using LUKS-encrypted partitions because CA operations can
be performed on any system that can run OpenSSL and has access to the KeePassXC
CLI tool. Additionally, the database can be freely stored and backed up in more
ways than block devices.

We'll create two databases: one to store all of the YubiKey secrets, Root CA
private key and certificate backup, as well as the Github App private key
(should you want to use the Github API to publish CA certificates and CRLs); the
second database will store a single `yubikey` entry where ***only*** the PIV PIN
number will be stored

The database containing only the YubiKey PIV PIN is to prevent access to all CA
secrets when CA operations are being performed.

This example will use a block storage device for CA data, though this could be
accomplished with a directory archive if you don't want to manage additional
loose storage devices.

This example will reference the KDBX database files as being located in the root
of the `CADATA` directory. It should be safe to keep the `yubikey.kdbx` file
here, but the `root-ca.kdbx` file should be moved somewhere else for safe
keeping.

## Provisioner CADATA Device

This example uses a 32GB USB drive.

Store the device path of the drive in an environment variable:

```sh
DEVICE=/dev/sdb
```

### Wipe Device

Use `wipefs` to clear all partitions, then use it again to clear the base
device:

```sh
sudo wipefs -af "${DEVICE}*"
```

```sh
sudo wipefs -af $DEVICE
```

### Create Partition

!!! note
    If you have `sgdisk` available, formatting can be accomplished with the
    following one-liner:

    ```sh
    sudo sgdisk \
    -n 1:: \
    -t 1:0700 \
    -c 1:CADATA \
    $DEVICE
    ```

    If you do this, skip ahead to [Format Partition](#format-partition).

```sh
sudo fdisk $DEVICE
```

Create a new GPT partition table:

```{.sh .no-copy}
Command (m for help): g
Created a new GPT disklabel (GUID: 26BAC14C-5FF5-44F2-B138-CCBD19EDBDC2).
```

Create a new partition and set the partition type GUID to
`Microsoft basic data`:

```txt title="Microsoft basic data partition type GUID"
EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
```

```{.sh .no-copy}
Command (m for help): n
Partition number (1-128, default 1): 
First sector (2048-123174878, default 2048): 
Last sector, +/-sectors or +/-size{K,M,G,T,P} (2048-123174878, default 123172863): 

Created a new partition 1 of type 'Linux filesystem' and of size 58.7 GiB.

Command (m for help): t
Selected partition 1
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

### Format Partition

```sh
sudo mkfs.exfat -L CADATA "${DEVICE}1"
```

```{.sh .no-copy}
exfatprogs version : 1.2.5
Creating exFAT filesystem(/dev/sdb1, cluster size=131072)

Writing volume boot record: done
Writing backup volume boot record: done
Fat table creation: done
Allocation bitmap creation: done
Upcase table creation: done
Writing root directory entry: done
Synchronizing...

exFAT format complete!
```

### Mount Partition

Create a mount point for the `CADATA` partition:

```sh
USERNAME=${USER:-$(id -un)}
GROUPID=$(id -g)
```

```sh
sudo mkdir -p /run/media/$USERNAME/CADATA
```

```sh
sudo mount "${DEVICE}1" /run/media/$USERNAME/CADATA \
    -o uid=$USERNAME -o gid=$GROUPID
```

```sh
export CADATAPATH=/run/media/$USERNAME/CADATA
```

## Create Databases

### root-ca.kdbx

The `keepassxc-cli` `-t` option specifies the ammount of milliseconds it will
take to encrypt/decrypt the database. Longer times help the database be more
resistant to brute-force attacks. `-t` must be between 0 and 5000 (0 and
5 seconds).

A 5-scond time is used for the `root-ca.kdbx` file since it will contain the
most critical secrets:

```sh
keepassxc-cli db-create -p -t 5000 $CADATAPATH/root-ca.kdbx
```

You will be prompted for a password and to repeat it:

```{.sh .no-copy}
Enter password to encrypt database (optional): 
Repeat password: 
Benchmarking key derivation function for 5000ms delay.
Setting 326086976 rounds for key derivation function.
Successfully created new database.
```

Add entries for `rootca` and `yubikey`. If you're using a Github App to publish
CA changes, then also add an entry for `github` to store the App's private key.
`yubikey` will be used to store files containing the Management Key, PIN Unlock
Key, and PIN.


!!! note
    Each command will take the amount of time you configured to decrypt **AND**
    re-encrypt. So if you chose `5000`, each command will take a minimum of 10
    seconds, with extra time depending on the speed of your storage device.

```sh
keepassxc-cli add $CADATAPATH/root-ca.kdbx root-ca
```

```sh
keepassxc-cli add $CADATAPATH/root-ca.kdbx yubikey
```

```sh
keepassxc-cli add $CADATAPATH/root-ca.kdbx github
```

### yubikey.kdbx

A 1 second time is used here since the PIN is easier to change if it is
accidentally leaked. Though, when performing CA operations, the PIN will be
loaded into a session keyring, so a longer decryption time shouldn't be that
much of a problem.

```sh
keepassxc-cli db-create -p -t 1000 $CADATAPATH/yubikey.kdbx
```

``` {.sh .no-copy}
Enter password to encrypt database (optional): 
Repeat password: 
Benchmarking key derivation function for 1000ms delay.
Setting 58823528 rounds for key derivation function.
Successfully created new database.
```

Add an entry named `yubikey`. This will be used to store a file attachment
containing the PIN number:

```sh
keepassxc-cli add $CADATAPATH/yubikey.kdbx yubikey
```

## (Optional) Store KeePassXC in CADATA

Storing a copy of the KeePassXC application in `CADATA` could improve
portability. If you wish to do this, I would recommend downloading versions for
every OS type you have access to: the Linux AppImage, the Windows portable ZIP,
Intel macOS `.dmg`, and Apple Silicon macOS `.dmg` versions are available.

```sh
mkdir /run/media/$USERNAME/CADATA/keepassxc
```

```sh
mv ~/Downloads/KeePassXC-*.AppImage /run/media/$USERNAME/CADATA/keepassxc
```

```sh
mv ~/Downloads/KeePassXC-*.zip /run/media/$USERNAME/CADATA/keepassxc
```

```sh
mv ~/Downloads/KeePassXC-*.dmg /run/media/$USERNAME/CADATA/keepassxc
```

## Unmount CADATA

```sh
sudo umount "${DEVICE}1"
```
