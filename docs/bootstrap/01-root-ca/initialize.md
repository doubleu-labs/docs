# Initialize Root CA

Select the tab associated with the storage method used.

## Mount Storage

Gather your username and group ID:

```sh
USERNAME=${USER:-$(id -un)}
GROUPID=$(id -g)
```

Set a variable containing the block device path:

```sh
DEVICE=/dev/sdb
```

=== "Block Device"

    Create mount points for the `ROOTCASEC`, `YKPIN`, and `CADATA` partitions:

    ```sh
    sudo mkdir -p /run/media/$USERNAME/{YUBISEC,ROOTCASEC,YKPIN,CADATA}
    ```

    Mount the `YUBISEC` partition:

    ```sh
    YUBISEC_PART="${DEVICE}1"
    YUBISEC_UUID=$(sudo cryptsetup luksUUID $YUBISEC_PART)
    ```

    ```sh
    sudo cryptsetup open $YUBISEC_PART --type=luks "luks-${YUBISEC_UUID}"
    ```

    ```sh
    sudo mount "/dev/mapper/luks-${YUBISEC_UUID}" /run/media/$USERNAME/YUBISEC \
        -o uid=$USERNAME -o gid=$GROUPID
    ```


    Mount the `ROOTCASEC` partition:

    ```sh
    ROOTCASEC_PART="${DEVICE}2"
    ROOTCASEC_UUID=$(sudo cryptsetup luksUUID $ROOTCASEC_PART)
    ```

    ```sh
    sudo cryptsetup open $ROOTCASEC_PART --type=luks "luks-${ROOTCASEC_UUID}"
    ```

    ```sh
    sudo mount "/dev/mapper/luks-${ROOTCASEC_UUID}" /run/media/$USERNAME/ROOTCASEC \
        -o uid=$USERNAME -o gid=$GROUPID
    ```

    Mount the `YKPIN` partition:

    ```sh
    YKPIN_PART="${DEVICE}3"
    YKPIN_UUID=$(sudo cryptsetup luksUUID $YKPIN_PART)
    ```

    ```sh
    sudo cryptsetup open $YKPIN_PART --type=luks "luks-${YKPIN_UUID}"
    ```
    
    ```sh
    sudo mount "/dev/mapper/luks-${YKPIN_UUID}" /run/media/$USERNAME/ROOTCASEC \
        -o uid=$USERNAME -o gid=$GROUPID
    ```

    Mount the `CADATA` partition:

    ```sh
    CADATA_PART="${DEVICE}4"
    CADATA_UUID=$(sudo cryptsetup luksUUID $CADATA_PART)
    ```

    ```sh
    sudo cryptsetup open $CADATA_PART --type=luks "luks-${CADATA_UUID}"
    ```

    ```sh
    sudo mount "/dev/mapper/luks-${CADATA_UUID}" /run/media/$USERNAME/ROOTCASEC \
        -o uid=$USERNAME -o gid=$GROUPID
    ```

    Set environment variables containing paths to each partition, ensuring that
    the `CADATPATH` variable is exported:

    ```sh
    YUBISECPATH=/run/media/$USERNAME/YUBISEC
    ROOTCASECPATH=/run/media/$USERNAME/ROOTCASEC
    YKPINPATH=/run/media/$USERNAME/YKPIN
    export CADATAPATH=/run/media/$USERNAME/CADATA
    ```

=== "KDBX Database"

    Create a mount point for the `CADATA` device:

    ```sh
    sudo mkdir -p /run/media/$USERNAME/CADATA
    ```

    Mount the `CADATA` device with ownership:
    
    ```sh
    sudo mount "${DEVICE}1" /run/media/$USERNAME/CADATA \
        -o uid=$USERNAME -o gid=$GROUPID
    ```

    Set and export the `CADATAPATH` environment variable to the `CADATA`
    partition mounted path:

    ```sh
    export CADATAPATH=/run/media/$USERNAME/CADATA
    ```

## Generate YubiKey Secrets

=== "Block Device"

    Generate a new Management Key containing 48 upper-case hexidecimal
    characters:

    ```sh
    < /dev/urandom tr -d '[:lower:]' | tr -cd '[:xdigit:]' | head -c48 \
    > $YUBISECPATH/ManagementKey
    ```

    Generate a new PIN Unlock Key containing 8 digits:

    ```sh
    < /dev/urandom tr -cd '[:digit:]' | head -c8 \
    > $YUBISECPATH/PINUnlockKey
    ```

    Generate a new PIN containing 6 digits:

    ```sh
    < /dev/urandom tr -cd '[:digit:]' | head -c6 \
    > $YUBISECPATH/PIN
    ```

    Copy the file containing the PIN to the `YKPIN` partition:

    ```sh
    cp $YUBISECPATH/PIN $YKPINPATH/PIN
    ```

=== "KDBX Database"

    We're going to use a temporary Kernel Keyring session to store our generated
    secrets. Trying to generate secrets directly into the database then
    immediately use those secrets to provision everything can get frustrating
    due to the contant-time security parameter of the database (up to 5 seconds
    for ***each*** transaction).

    ```sh
    keyctl session
    ```

    If you're not using the default shell, set the `SHELL` variable to the shell
    binary path. For example ZSH when Bash is the default:

    ```sh
    SHELL=/bin/zsh keyctl session
    ```

    Generate new YubiKey secrets into the keyring. `keyctl` returns the keyring
    ID number of the secret, so store it in an environment variable prefixed
    with `KEYID_` for future use.

    Generate a new Management Key containing 48 upper-case hexidecimal
    characters:

    ```sh
    KEYID_YKMGMT=$(
        < /dev/urandom tr -d '[:lower:]' | tr -cd '[:xdigit:]' | head -c48 | \
        keyctl padd user yk-mgmtkey @s
    )
    ```

    Generate a new PIN Unlock Key containing 8 digits:

    ```sh
    KEYID_YKPUK=$(
        < /dev/urandom tr -cd '[:digit:]' | head -c8 | \
        keyctl padd user yk-puk @s
    )
    ```

    Generate a new PIN containing 6 digits:

    ```sh
    KEYID_YKPIN=$(
        < /dev/urandom tr -cd '[:digit:]' | head -c6 | \
        keyctl padd user yk-pin @s
    )
    ```

    Inspect the keyring to show the stored secrets:

    ```sh
    keyctl show @s
    ```

    ```sh
    $ keyctl show @s
    Keyring
     746496298 --alswrv   1000  1000  keyring: _ses
     867868241 --alswrv   1000  1000   \_ user: yk-mgmtkey
     553791613 --alswrv   1000  1000   \_ user: yk-pin
     323468437 --alswrv   1000  1000   \_ user: yk-puk
    ```

    Write the Management Key to the `root-ca.kdbx` secret database as a file
    attachment named `ManagementKey` under the `yubikey` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/root-ca.kdbx \
    yubikey \
    ManagementKey \
    <(keyctl print $KEYID_YKMGMT)
    ```

    Write the PIN Unlock Key to the `root-ca.kdbx` secret database as a file
    attachment named `PINUnlockKey` under the `yubikey` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/root-ca.kdbx \
    yubikey \
    PINUnlockKey \
    <(keyctl print $KEYID_YKPUK)
    ```

    Write the PIN to the `root-ca.kdbx` secret database as a file attachment
    named `PIN` under the `yubikey` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/root-ca.kdbx \
    yubikey \
    PIN \
    <(keyctl print $KEYID_YKPIN)
    ```

    Finally, copy the PIN into the PIN database as a file attachment named `PIN`
    under the `yubikey` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/pin.kdbx \
    yubikey \
    PIN \
    <(keyctl print $KEYID_YKPIN)
    ```

## Initialize YubiKey

Clear the YubiKey PIV application.

!!! warning
    Maks sure only the correct YubiKey device is connect. This will erase all
    PIV certificates and private keys.

```sh
ykman piv reset
```

Override the `LC_CTYPE` variable so secret generation is language-agnostic:

```sh
export LC_CTYPE=C
```

Import the new Management Key:

=== "Block Device"

    ```sh
    yubico-piv-tool \
    --action=set-mgm-key \
    --new-key=$(cat $YUBISECPATH/ManagementKey)
    ```

=== "KDBX Database"

    ```sh
    yubico-piv-tool \
    --action=set-mgm-key \
    --new-key=$(keyctl print $KEYID_YKMGMT)
    ```

Import the new PIN Unlock Key using the default `12345678` as the existing PUK:

=== "Block Device"

    ```sh
    yubico-piv-tool \
    --action=change-puk \
    --pin=12345678 \
    --key=$(cat $YUISECPATH/ManagementKey) \
    --new-pin=$(cat $YUBISECPATH/PINUnlockKey)
    ```

=== "KDBX Database"

    ```sh
    yubico-piv-tool \
    --action=change-puk \
    --pin=12345678 \
    --key=$(keyctl print $KEYID_YKMGMT) \
    --new-pin=$(keyctl print $KEYID_YKPUK)
    ```

Finally, import the new PIN using the default `123456` as the existing PIN:

=== "Block Device"

    ```sh
    yubico-piv-tool \
    --action=change-puk \
    --pin=123456 \
    --key=$(cat $YUBISECPATH/ManagementKey) \
    --new-pin=$(cat $YUBISECPATH/PIN)
    ```

=== "KDBX Database"

    ```sh
    yubico-piv-tool \
    --action=change-puk \
    --pin=123456 \
    --key=$(keyctl print $KEYID_YKMGMT) \
    --new-pin=$(keyctl print $KEYID_YKPIN)
    ```

## Bootstrap CA Data

Generate the CA data directory structure:

```sh
mkdir $CADATAPATH/{ca,certs,crl,db}
```

Generate a 40-character upper-case hexidecimal string for the first certificate
serial number:

```sh
< /dev/urandom tr -d '[:lower:]' | tr -cd '[:xdigit:]' | head -c40 \
> $CADATAPATH/db/ca.crt.serial
```

Set the first CRL serial number:

```sh
echo 1000 > $CADATAPATH/db/ca.crl.serial
```

Create an empty file that will contain the OpenSSL CA database. This is required
for OpenSSL to run:

```sh
touch $CADATAPATH/db/ca.db
```

Copy the PKCS11 module configuration from the cloned `bootstrap` repository at
`LABBOOTSTRAPPATH` to the root of `CADATAPATH`:

```sh
cp $LABBOOTSTRAPPATH/root-ca/pkcs11.cnf $CADATAPATH/pkcs11.cnf
```

Set the AIA and CDP URLs that the Root CA will include in signed certificates.
These values will differ for your environment:

```sh
export AIAURL="http://ca.doubleu.codes/DoubleU_Root_CA_01.crt"
export CDPURL="http://ca.doubleu.codes/DoubleU_Root_CA_01.crl"
```

Read the OpenSSL CA configuration file from the cloned `bootstrap` repository at
`LABBOOTSTRAPPATH` into `envsubst` and output the rendered file to the root of
`CADATAPATH`:

```sh
envsubst '$AIAURL $CDPURL' \
< $LABBOOTSTRAPPATH/root-ca/openssl.cnf.tpl \
> $CADATAPATH/openssl.cnf
```

## Initialize Root CA

=== "Block Device"

    Create the CA primary key and store it in `ROOTCASECPATH`. It isn't
    encrypted here because it should only be stored on the encrypted `ROOTCASEC`
    partition. If you would still like to encrypt it with a password, add the
    `-aes256` argument:

    ```sh
    openssl genpkey \
    -algorighm ec \
    -pkeyopt ec_paramgen_curve:P-384 \
    -pkeyopt ec_param_enc:named_curve \
    -out $ROOTCASECPATH/ca.key.pem
    ```

    Generate the public key from the CA private key and store it in 
    `ROOTCASECPATH`. This is used by `yubico-piv-tool` to generate the
    Certificate Signing Request (CSR):

    ```sh
    openssl pkey -pubout \
    -in $ROOTCASEC/ca.key.pem \
    -out $ROOTCASEC/ca.pub.pem
    ```

=== "KDBX Database"

    Create the CA private key and store it in the keyring. It isn't encrypted
    here because it should only be stored in the encrypted
    `$CADATAPATH/root-ca.kdbx` database file. If you would still like to protect
    it with a password, then add the `-aes256` argument to the OpenSSL portion
    of the command:

    ```sh
    KEYID_CAPRIVATEKEY=$(
        openssl genpkey \
        -algorithm ec \
        -pkeyopt ec_paramgen_curve:P-384 \
        -pkeopt ec_patam_enc:named_curve | \
        keyctl padd user ca-privatekey @s
    )
    ```

    Write the CA private key to the `root-ca.kdbx` secret database as a file
    attachment named `ca.key.pem` under the `root-ca` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/root-ca.kdbx \
    root-ca \
    ca.key.pem \
    <(keyctl pipe $KEYID_CAPRIVATEKEY)
    ```

    Generate the public key from the CA private key on the keyring. This is used
    by `yubico-piv-tool` to generate the Certificate Signing Request (CSR):

    ```sh
    KEYID_CAPUBLICKEY=$(
        openssl pkey -pubout \
        -in <(keyctl pipe $KEYID_CAPRIVATEKEY) | \
        keyctl padd user ca-publickey @s
    )
    ```

    Write the CA public key to the `root-ca.kdbx` secret database as a file
    attachement named `ca.pub.pem` under the `root-ca` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/root-ca.kdbx \
    root-ca \
    ca.pub.pem \
    <(keyctl pipe $KEYID_CAPUBLICKEY)
    ```

Import the private key into the YubiKey Slot 1 (9a):

=== "Block Device"

    ```sh
    yubico-piv-tool \
    --action=import-key \
    --slot=9a \
    --key-format=PEM \
    --key=$(cat $YUBISECPATH/ManagementKey) \
    --input=$ROOTCASECPATH/ca.key.pem
    ```

=== "KDBX Database"

    ```sh
    yubico-piv-tool \
    --action=import-key \
    --slot=9a \
    --key-format=PEM \
    --key=$(keyctl print $KEYID_YKMGMT) \
    --input=<(keyctl pipe $KEYID_CAPRIVATEKEY)
    ```

Set the Root CA Subject to prepare for creating the Root CA CSR. Ensure that the
string begins and ends with a `/`, and also conforms to the `[match_pol]` policy
defined in `$CADATAPATH/openssl.cnf`.

Your Subject will be different.

```sh
CASUBJECT='/CN=DoubleU Root CA 01/O=DoubleU Labs/C=US/DC=doubleu/DC=codes/'
```

Create the CSR:

=== "Block Device"

    ```sh
    yubico-piv-tool \
    --action=verify-pin \
    --action=request-certificate \
    --slot=9a \
    --subject=$CASUBJECT \
    --pin=$(cat $YKPINPATH/PIN) \
    --input=$ROOTCASECPATH/ca.pub.pem \
    --output=$CADATAPATH/ca/ca.csr.pem
    ```

=== "KDBX Database"

    ```sh
    yubico-piv-tool \
    --action=verify-pin \
    --action=request-certificate \
    --slot=9a \
    --subject=$CASUBJECT \
    --pin=$(keyctl print $KEYID_YKPIN) \
    --input=<(keyctl pipe $KEYID_CAPUBLICKEY) \
    --output=$CADATAPATH/ca/ca.csr.pem
    ```

    Write the CA CSR to the `root-ca.kdbx` secret database as a file attachment
    named `ca.csr.pem` under the `root-ca` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/root-ca.kdbx \
    root-ca \
    ca.csr.pem \
    $CADATAPATH/ca/ca.csr.pem
    ```

Set the number of years the Root CA will be valid in an environment variable:

```sh
CAYEARS=20
```

Set the `STARTDATE` and `ENDDATE` validity periods for the CA certificate in
environment variables. The `STARTDATE` will be set to midnight on New Year's Day
of the current year. The `ENDDATE` will be the same time of day with `CAYEARS`
added to the current year. This date fudging is to obscure the time the 
certificate is signed.

```sh
STARTDATE=$(date -d $(date +'%Y0101') +'%Y%m%d%H%M%SZ')
ENDDATE=$(date -d "$(($(date +'%Y') + $CAYEARS))0101" +'%Y%m%d%H%M%SZ')
```

Self-sign the Root CA CSR:

=== "Block Device"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -selfsign \
    -batch \
    -passin "file:${YKPINPATH}/PIN" \
    -extensions root_ca_ext \
    -startdate $STARTDATE \
    -enddate $ENDDATE \
    -in $CADATAPATH/ca/ca.csr.pem \
    -out $CADATAPATH/ca/ca.crt.pem
    ```

=== "KDBX Database"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -selfsign \
    -batch \
    -passin file:<(keyctl pipe $KEYID_YKPIN) \
    -extensions root_ca_ext \
    -startdate $STARTDATE \
    -enddate $ENDDATE \
    -in $CADATAPATH/ca/ca.csr.pem \
    -out $CADATAPATH/ca/ca.crt.pem
    ```

Re-encode the Root CA certificate to binary (DER) format. This is what will be
published to the `AIAURL`.
[RFC 5280 § 4.2.2.1](https://datatracker.ietf.org/doc/html/rfc5280#section-4.2.2.1)
mandates that this file `MUST` be DER-encoded.

```sh
openssl x509 \
-outform der \
-in $CADATAPATH/ca/ca.crt.pem \
-out $CADATAPATH/ca/ca.crt
```

Install the certificate to the YubiKey PIV Slot 1 (9a):

=== "Block Device"

    ```sh
    yubico-piv-tool \
    --action=import-certificate \
    --slot=9a \
    --key=$(cat $YUBISECPATH/ManagementKey) \
    --input=$CADATAPATH/ca/ca.crt.pem
    ```

=== "KDBX Database"

    ```sh
    yubico-piv-tool \
    --action=import-certificate \
    --slot=9a \
    --key=$(keyctl print $KEYID_YKMGMT) \
    --input=$CADATAPATH/ca/ca.crt.pem
    ```

    Write the Root CA Certificate to the `root-ca.kdbx` secret database as a
    file attachment named `ca.crt.pem` under the `root-ca` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/root-ca.kdbx \
    root-ca \
    ca.crt.pem \
    $CADATAPATH/ca/ca.crt.pem
    ```

## Create Initial Certificate Revocation List (CRL)

The default validity period is set in the `$CADATAPATH/openssl.cnf` with the
option `default_crl_days`. By default, this is set to `180` days, or 6 months.
This can be extended, but should realistically be no more that 365, or 1 year.

```ini
[root_ca]
. . .
default_crl_days = 180
```

Create the initial CRL:

=== "Block Device"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -gencrl \
    -passin "file:${YKPINPATH}/PIN" \
    -out $CADATAPATH/crl/ca.crl.pem
    ```

=== "KDBX Database"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -gencrl \
    -passin file:<(keyctl pipe $KEYID_YKPIN) \
    -out $CADATAPATH/crl/ca.crl.pem
    ```

Re-encode the Root CA CRL to binary (DER) format. This is what will be published
to the `CDPURL`.
[RFC 5280 § 4.2.1.13](https://datatracker.ietf.org/doc/html/rfc5280#section-4.2.1.13)
mandates that this file `MUST` be DER-encoded.

```sh
openssl crl \
-outform der \
-in $CADATAPATH/crl/ca.crl.pem \
-out $CADATAPATH/crl/ca.crl
```

## Initialize Github App

If you plan to manually publish your Certificate and CRL, you can skip to the
[next section](#environment-cleanup)

Now, we'll set up the publishing of the Root CA Certificate and CRL to Github
Pages using our Github App, making these files available.

You downloaded the Github App private key to your browser's default `Downloads`
directory. If you haven't done so, check back in at
[Getting Started](../getting_started/#github-app) for instructions.

!!! note
    You'll need to note the App ID from the Github App's settings page (the same
    page the private key is generated on).

=== "Block Device"

    Move the Github App's private key from your `Downloads` directory to the
    `ROOTCASEC` directory to back it up.

    ```sh
    mv ~/Downloads/github-app.2001-01-01.private-key.pem $ROOTCASECPATH
    ```

    Load it on the YubiKey PIV Slot 3 (9d):

    ```sh
    yubico-piv-tool \
    --action=import-key \
    --slot=9d \
    --key-format=PEM \
    --key=$(cat $YUBISECPATH/ManagementKey) \
    --input=$ROOTCASECPATH/github-app.2001-01-01.private-key.pem
    ```

=== "KDBX Database"

    Copy the contents of the Github App private key into the keyring:

    ```sh
    KEYID_APPKEY=$(
        cat ~/Downloads/github-app.2001-01-01.private-key.pem | \
        keyctl padd user app-privatekey @s
    )
    ```

    Write the Github App private key to the `root-ca.kdbx` secret database as a
    file attachment named `AppKey` under the `github` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/root-ca.kdbx \
    github \
    AppKey \
    <(keyctl pipe $KEYID_APPKEY)
    ```

    Delete the private key file:

    ```sh
    rm ~/Downloads/github-app.2001-01-01.private-key.pem
    ```

    Load it on the YubiKey PIV Slot 3 (9d):

    ```sh
    yubico-piv-tool \
    --action=import-key \
    --slot=9d \
    --key-format=PEM \
    --key=$(keyctl print $KEYID_YKMGMT) \
    --input=<(keyctl pipe $KEYID_APPKEY)
    ```

Create a dummy self-signed certifiate from the App's private key. This has no
actual utility outside of making it easier to identify the YubiKey's Slot 3 (9d)
as occupied.

The `CommonName` can be anything, but I suggest that it be something easily
recognizable, for example `/O=Github App/OU=[APP ID]/CN=App Name/`.

=== "Block Device"

    ```sh
    openssl x509 \
    -new \
    -subj '/O=Github App/OU=123456/CN=My Github App/' \
    -key $ROOTCASECPATH/github-app.2001-01-01.private-key.pem \
    -out $ROOTCASECPATH/github-app.2001-01-01.dummy-certificate.pem
    ```

=== "KDBX Database"

    ```sh
    KEYID_APPCERT=$(
        openssl x509 \
        -new \
        -subj '/O=Github App/OU=123456/CN=My Github App/' \
        -key <(keyctl pipe $KEYID_APPKEY) | \
        keyctl padd user app-dummycert @s
    )
    ```

    Write the Github App dummy certificate to the `root-ca.kdbx` secret database
    as a file attachment named `AppCert` under the `github` key:

    ```sh
    keepassxc-cli attachment-import \
    $CADATAPATH/root-ca.kdbx \
    github \
    AppCert \
    <(keyctl pipe $KEYID_APPCERT)
    ```

Install the certificate to the YubiKey's PIV Slot 3 (`9d`):

=== "Block Device"

    ```sh
    yubico-piv-tool \
    --action=import-certificate \
    --slot=9d \
    --key=$(cat $YUBISECPATH/ManagementKey) \
    --input=$ROOTCASECPATH/github-app.2001-01-01.dummy-certificate.pem
    ```

=== "KDBX Database"

    ```sh
    yubico-piv-tool \
    --action=import-certificate \
    --slot=9d \
    --key=<(keyctl pipe $KEYID_YKMGMT) \
    --input=<(keyctl pipe $KEYID_APPCERT)
    ```

Create `$CADATAPATH/deploy.env` containing information needed to publish files
to the Github repository using the Github API:

```INI title="$CADATAPATH/deploy.env"
DEPLOY_APP_ID=123456
DEPLOY_REPO_OWNER="doubleu-labs"
DEPLOY_REPO_NAME="ca"
DEPLOY_REPO_BRANCH="master"
DEPLOY_AIA_FILE="DoubleU_Root_CA_01.crt"
DEPLOY_CDP_FILE="DoubleU_Root_CA_01.crl"
```

## Environment Cleanup

=== "Block Device"

    Unmount the volumes, remove the mount point, and close the LUKS volumes.

    ```sh
    sudo unmount /run/media/$USERNAME/{YUBISEC,ROOTCASEC,YKPIN,CADATA}
    ```

    ```sh
    rm -rf /run/media/$USERNAME/{YUBISEC,ROOTCASEC,YKPIN,CADATA}
    ```

    ```sh
    sudo cryptsetup close "luks-${YUBISEC_UUID}"
    ```

    ```sh
    sudo cryptsetup close "luks-${ROOTCASEC_UUID}"
    ```

    ```sh
    sudo cryptsetup close "luks-${YKPIN_UUID}"
    ```

=== "KDBX Database"

    Since all secrets are stored in the session keyring, this can be cleared by
    exiting the current shell session created earlier by `keyctl session`:

    ```sh
    exit
    ```
