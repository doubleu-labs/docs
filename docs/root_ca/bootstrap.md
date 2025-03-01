# Bootstrap CA

Now we'll actually create the CA.

## Prepare the YubiKey

Insert the YubiKey and make sure it's detected:

```sh
ykman list
```

You should see something similar to the following:

```{ .raw .no-copy }
YubiKey 5 Nano (5.4.3) [OTP+FIDO+CCID] Serial: 01234567
```

Check that all YubiKey PIV slots are empty and all of the secrets are default.

```sh
ykman piv info
```

If the YubiKey is ready, you should see no `Slot` information, and there should
be a `WARNING` notifying you that you are using the default `PIN`, `PUK`, and
`Management Key`.

```{ .raw .no-copy }
PIV version:              5.4.3
PIN tries remaining:      3/3
PUK tries remaining:      3/3
Management key algorithm: TDES
WARNING: Using default PIN!
WARNING: Using default PUK!
WARNING: Using default Management key!
CHUID: No data available
CCC:   No data available
```

If the YubiKey has any occupied slots or any of the secrets are not set to the
default values, it will need to be reset.

```sh
ykman piv reset
```

The YubiKey should now be prepared for use as the store for the CA private key.

!!! note
    Leave the YubiKey connected for the remainder of this process.

## Setup `ca-boostrap` Toolkit

Create a suitable empty working directory and clone the
[`ca-bootstrap`](https://github.com/doubleu-labs/ca-bootstrap) toolkit into it:

```sh
git clone https://github.com/doubleu-labs/ca-bootstrap .
```

Run the setup script:

```sh
./scripts/setup.sh
```

This will create all of the required directories for CA initialization.

Copy the Github App private key that was downloaded earlier to the `./secrets`
directory.

### Configure `ca.env`

CA Configuration:

- `CA_KEY_SPEC`: Choose between an RSA or ECDSA CA private key algorithm. Key
  sizes are restricted here for simplicity. - Valid RSA key sizes are: - `RSA-3072` - `RSA-4096` - Valid ECDSA key sizes are: - `P-384`
- `CA_YEARS`: The number of years your CA should be valid for.
    - `20` should be a good value as it will probably outlive your
    infrastructure if you're a Homelab user.
- `CA_SUBJECT`: An OpenSSL-format Distinguished Name (DN).
    - Must begin and end with, as well as each field delimited by, a `/`.
    - Example: `/CN=My Root CA 01/L=New York/S=New York/C=US/O=My Org/`

Deployment Configuration:

- `DEPLOY_APP_ID`: The App ID or Client ID of your Github App
- `DEPLOY_APP_KEY`: The file name of your App's private key within the
  `./secrets` directory.
- `DEPLOY_REPO_OWNER`: The owner (user or organization) of the CA repository
- `DEPLOY_REPO_NAME`: The name of the CA repository
- `DEPLOY_REPO_BRANCH`: The branch that CA assets will be deployed to
    - Also the branch that Github Pages will deploy from.
- `DEPLOY_PAGES_CUSTOM_DOMAIN`: (Optional) The custom domain CA assets will be
  accessed from. - Leave this variable blank if you'll be using the default Github Pages URL
  `<OWNER>.github.io/<REPOSITORY>`
- `DEPLOY_AIA_FILE`: The file name of your CA certificate as it will appear in
  the repository.
- `DEPLOY_CDP_FILE`: The file name of your CA CRL as it will appear in the
  repository.

### (Optional) Modify `openssl.template.cnf`

There are a few options in the OpenSSL configuration file that you may want to
change.

By default, Intermediate/Issuing CA certificates will be valid for 10 years
(3652 days). If you chose a `CA_YEARS` values less than that, you will want to
change this to be less than the value that you chose in days.

```ini
[root_ca]
. . .
default_days = 3652
```

By default, the CA CRL will expire every 6 months (180 days). If you want to
change this, then modify the following key:

```ini
[root_ca]
. . .
default_crl_days = 180
```

The final section you should consider is the DN Match Policy. This will restrict
or modify the DN of Intermediate/Issuing Certificates that this CA will sign.

Valid values are:

- `optional`: This field, if contained in a CSR DN, will be copied to the signed
  certificate.
- `supplied`: This field **_MUST_** be present in the CSR DN
- `match`: This field **_MUST MATCH_** the corresponding field of the Root CA
  certiciate.

Any fields **_not present_** on the match policy will be stripped from the
signed certificate if present in the CSR DN.

!!! example
    If you have the Locality (`L`), State (`S`), and Country (`C`) set on your
    Root Certificate, and want these fields to match:

    ```ini
    [match_pol]
    commonName             = supplied
    localityName           = match
    stateOrProvinceName    = match
    organizationName       = optional
    organizationalUnitName = optional
    countryName            = match
    domainComponent        = optional
    ```

!!! example
    If you have a Domain Component (`DC`) set on your Root Certificate, such as
    `/CN=My Root CA 01/DC=example/DC=com/`, and you want **_ALL_** CSRs to
    specify the same `DC` (eg. `/CN=My Sub CA 01/DC=example/DC=com`):

    ```ini
    [match_pol]
    commonName             = supplied
    localityName           = optional
    stateOrProvinceName    = optional
    organizationName       = optional
    organizationalUnitName = optional
    countryName            = optional
    domainComponent        = match
    ```

## Initialize the CA

All that needs to be done now is to run the initialization script:

```sh
./scripts/initialize.sh
```

The script will verify that all required applications are available in your
`$PATH`, verify that the YubiKey is in a default state, verfiy that all
all directories are empty, validate variables defined in the `ca.env` file,
and finally verify that the the Github App has access to the target repository.

When everything is ready, you'll see a confirmation dialog similar to the
following:

```raw
==========================
=  Ready to initialize!  =
==========================

!!! Confirm CA Attributes and Deployment Environment!
!!! Your new Root Certificate Authority (CA) is ready to be created.
!!! Subject:
!!!     CN:     My Root CA 01
!!!     C:      US
!!! Key:        P-384
!!! Valid from: 01 January 2025 @ 00:00:00
!!! Valid to:   01 January 2045 @ 00:00:00
!!! AIA URL:    http://wranders.github.io/test/My_Root_CA_01.crt
!!! CDP URL:    http://wranders.github.io/test/My_Root_CA_01.crl

Do you want to continue? Type 'CONFIRM': CONFIRM
```

Type `CONFIRM` to create the CA.

When everything is complete, you will see a large dialog giving you instructions
on what to do next.

## Next

Next, we'll need to [modify the security settings of the secrets databases](./database_security/index.md).
