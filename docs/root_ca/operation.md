# CA Operation

To perform CA operations, you'll need the CA YubiKey and the CA archive file.

Place the CA archive file in an empty directory and unpack it:

```sh
tar -xvf rootca_20250101T121520Z.tar
```

## Sign Certificate Signing Requests (CSR)

!!! warning "Notice"
    CSRs signed by the Root using this script are assumed to be subordinate
    CAs themselves, ***not end-user certificates***.

    The Root is only configured to sign subordinate CAs.

To sign a CSR, run the following script:

```sh
./scripts/sign.sh -in <CSR> [ -out <CRT> ] [ -chain ] [ -force ]
```

Without the `-out` option, the certificate will be printed to `stdout`.

The `-chain` option will write the certiciate as a chained PEM file and include
the root CA certificate.

The `-force` option supresses the OpenSSL confirmation dialogs.

Since this operation adds the newly signed certificate to the `certs` directory
and adds and entry to the CA database, be sure to create a new archive of the
CA:

```sh
./scripts/archive.sh
```

## Revoke Certificates

To revoke a certificate, you'll need either the certificate file (which should
already be located in the `certs` directory) **OR** the serial number of the
certificate.

```sh
./scripts/revoke.sh -in <CRT> [ARGUMENTS]
```

or

```sh
./scripts/revoke.sh -serial <SERIAL> [ARGUMENTS]
```

!!! note
    If no arguments are specified, then the revocation reason is `unspecified`.
    A reason ***should*** be specified, so try not to do this.

The arguments and options are a little convoluted, and some not even useful, but
all revocation reasons supported by OpenSSL are included for completeness.

Here's a full list of supported revocation reasons:

- `-reason unspecified` (0): No reason given
- `-reason keyCompromise` (1): Entity's private key compromised
    - Requires `-date now` or `-date 20250101121520Z` (backdating recommended)
- `-reason CACompromise` (2): CA private key compromised, should only be used
    for revoking the Root itself.
    - Requires `-date now` or `-date 20250101121520Z` (backdating recommended)
- `-reason affiliationChanged` (3): Entity is no longer associated with the CA
- `-reason superseded` (4): Entity information changed and replaced, use the new
    certificate instead
- `-reason cessationOfOperation` (5): Entity is not longer operating
- `-reason certificateHold` (6): Certificate is temporarily revoked, not useful
    as unrevoke entries are typically published to delta CRLs, which are not
    implemented.
    - Requires `-instruction none`, `-instruction callIssuer`, or
    `-instruction reject`
- `-reason removeFromCRL`(8): Not useful, only used in delta CRLs which are not
    implemented.

The only reasons that are useful here are:

- `-reason keyCompromise`
- `-reason CACompromise`
- `-reason superseded`
- `-reason cessationOfOperation`

Revoking a certificate with this script immediately generates a new CRL.
Afterwards, you should deploy these changes to your CA repository using the
deploy script:

```sh
./scripts/deploy.sh -crl
```

Since this operation modifies the CA database and creates a new CRL file, be
sure to create a new archive of the CA:

```sh
./scripts/archive.sh
```

## Unrevoke Certificates

Unrevoking a certificate at the root level is ***really*** not a good idea, but
if a mistake was made before generating or publishing the CRL, then you *can*
unrevoke, but it is a manual process.

Open the `./db/ca.db` file in a text editor and make the following changes:

``` { .diff .no-copy }
  V	450101000000Z		3889F3B9B2FCD383EBA646ED30C58851B737C8EA	unknown	/CN=My Root CA 01/C=US
- R	350228173944Z	250228194850Z,keyTime,20250228194845Z	3889F3B9B2FCD383EBA646ED30C58851B737C8EB	unknown	/CN=My Test Issuing CA 01
+ V	350228173944Z		3889F3B9B2FCD383EBA646ED30C58851B737C8EB	unknown	/CN=My Test Issuing CA 01
```

In the first column, change `R` (revoked) to `V` (valid), then remove the data
in the third column that contains the revocation reason and associated data.

!!! warning
    This database file is `TAB` delimited. Be sure the retain that formatting.

Afterwards, run the script that only updates the CRL:

```sh
./scripts/update_crl.sh
```

This will generate a new CRL with an incremented CRL, so it should be adhered
to, but some clients may be confused if your previous revocation was included in
a previously published CRL.

Be sure to deploy the updated CRL:

```sh
./scripts/deploy.sh -crl
```

Since this operation modifies the CA database and creates a new CRL file, be
sure to create a new archive of the CA:

```sh
./scripts/archive.sh
```

## Upgrade Scripts

Occasionally, the `ca-bootstrap` toolkit may be updated to include scripts with
improvements and bug fixes. Since some of these scripts are copied to the CA
archive, you can update the scripts using the following script:

```sh
./scripts/upgrade_archive_scripts.sh -f rootca_20250101T121520Z.tar
```

This will unpack the archive into a temporary directory, replace the scripts,
then repack the CA into a new archive with an updated timestamp.
