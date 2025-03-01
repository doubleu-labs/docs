# Root Certificate Authority (CA) - Getting Started

These documents will guide you through initializing and deploying your own
internal YubiKey-backed offline Root CA to Github Pages. We'll do this so you
don't have to tie up any resources serving the Root CA certificate and the
associated Certificate Revocation List (CRL) on your own local infrastructure.

Initialization, deployment, and operation is done using a script-based toolkit.

The script toolkit used here currently only supports a single monolithic CRL
per CA. Complex revocation schemes such as scoped CRLs are not supported without
extensive modification to the scripts before the bootstrap process. Do so at
your own risk.

!!! note
    A binary toolkit that *will* support such schemes is in development, but not
    yet available.

!!! warning "NOTICE"
    The CA that you will create is ***ONLY*** intended to sign
    Intermediate/Issuing subordinate CAs, ***NOT*** end-user certificates.

## How This Works

1. (Optional) If you're using a custom domain, you'll need to create the
required DNS entries with your provider to connect your Github Pages deployment
to your domain.

2. You'll clone the later mentioned template repository. The only notable
feature in this repository is a Github Actions Workflow manifest that will
generate a (mostly) script-less static site that will serve as the landing page
for your CA. You'll need to make some modifications, but we'll get to that.

3. You'll need to create a Github App, install it to the user or organization
that owns the repository, and generate a new App private key.

4. You'll clone the
[`ca-bootstrap`](https://github.com/doubleu-labs/ca-bootstrap){target="\_blank"}
toolkit locally and initialize the Root CA.

5. You'll use the
[`ca-bootstrap`](https://github.com/doubleu-labs/ca-bootstrap){target="\_blank"}
toolkit to deploy your CA Certificate and initial CRL.

6. You'll modify the security settings of the two created KeePassXC databases to
fit your use and security concerns.

7. Next, you'll be shown how to create a self-contained archive of the
initialized Root CA using the
[`ca-bootstrap`](https://github.com/doubleu-labs/ca-bootstrap){target="\_blank"}
toolkit. This archive will be used for all future CA operations. You'll be given
quick demonstrations of various CA operations.

## Requirements

Things you'll need:

- A Github App to deploy your assets
- A YubiKey to dedicate to your Root CA
- A Linux-based OS with the following:
    - Commands:
        - `jq`
        - `keepassxc-cli`
        - `keyctl` (provided by `keyutils`)
        - `openssl`
        - `ykman`
        - `yubico-piv-tool`
    - Packages:
        - `openssl-pkcs11`

!!! note
    The package `openssl-pkcs11` provides a legacy OpenSSL Engine interface for
    the PKCS#11 standard. The OpenSSL 3 provider `pkcs11-provider` has not yet
    been validated to work with the toolkit used here.

## KeePassXC

This process makes heavy use of KeePassXC databases for storing long-term
backups of CA and YubiKey secrets, as well a using a small database containing
the YubiKey PIN to be programatically loaded during CA operation.

If you installed KeePassXC from your package manager, then you should already
have access to the `keepassxc-cli` command.

If you're using the AppImage, then you'll have to make an alias to gain access.
Make sure the AppImage file is executable.

```sh
chmod +x ${HOME}/Downloads/KeePassXC-*.AppImage
```

```sh
alias keepassxc-cli="${HOME}/Downloads/KeePassXC-*.AppImage cli"
```

This example assumes the AppImage is in your `Downloads` directory, but if you
use an installer or some integration tool, then it may be in a place like
`${HOME}/Applications`.

!!! danger "NOTICE"
    During the bootstrap process, both databases are secured with ***ONLY*** a
    1MB keyfile that is stored in the same directory as the databases.

    Unfortunately, it's not possible to change the security settings granularly
    using `keepassxc-cli`, so it ***MUST*** be done on the GUI application
    afterwards.

    If you delete these keyfiles before changing the security options, you'll
    have to purge the CA and start again as the database containing the YubiKey
    PIN will no longer be accessible.

## Next Step

If you're going to use a custom domain to access your CA, then
[continue to DNS configuraion](./dns/index.md).

If you're going to use the default `<USER>.github.io/<REPO>` URL then
[skip ahead to creating the CA template](./ca_template/index.md).

