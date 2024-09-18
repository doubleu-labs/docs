# Operation

## Mount Storage and Prepare Environment

```sh
DEVICE=/dev/sdb
USERNAME=${USER:-$(id -un)}
GROUPID=$(id -g)
```

=== "Block Device"

    ```sh
    sudo mkdir -p /run/media/$USERNAME/{YKPIN,CADATA}
    ```

    ```sh
    YKPIN_PART="${DEVICE}3"
    YKPIN_UUID=$(sudo cryptsetup luksUUID $YKIPN_PART)
    ```

    ```sh
    sudo mount "/dev/mapper/luks-${YKPIN_UUID}" /run/media/$USERNAME/YKPIN \
        -o uid=$USERNAME -o gid=$GROUPID
    ```

    ```sh
    sudo mount "${DEVICE}4" /run/media/$USERNAME/CADATA \
        -o uid=$USERNAME -o gid=$GROUPID
    ```

    ```sh
    YKPINPATH=/run/media/$USERNAME/YKPIN
    export CADATAPATH=/run/media/$USERNAME/CADATA
    ```

=== "KDBX Database"

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

    === "Default Shell"

        ```sh
        keyctl session
        ```

    === "Non-Default Shell"
    
        ```sh
        SHELL=/bin/zsh keyctl shell
        ```

    ```sh
    KEYID_YKPIN=$(
        keepassxc-cli attachment-import --stdout \
        $CADATAPATH/yubikey.kdbx \
        yubikey \
        PIN | \
        keyctl padd user yk-pin @s
    )
    ```

## Sign Certificate

=== "Block Device"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -passin "file:${YKPINPATH}/PIN" \
    -extensions issuing_ca_ext \
    -in [REQUEST].csr \
    -out [CERTIFICATE].crt.pem
    ```

=== "KDBX Database"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -passin file:<(keyctl pipe $KEYID_YKPIN) \
    -extensions issuing_ca_ext \
    -in [REQUEST].csr \
    -out [CERTIFICATE].crt.pem
    ```

```sh
cat [CERTIFICATE].crt.pem $CADATAPATH/ca/ca.crt.pem > [CERTIFICATE].chain.crt.pem
```

## Revoke Certificate

Revoke reasons:

- `unspecified`
- `keyCompromise`
    - Implied by `-crl_compromise YYYMMDDHHMMSSZ`
- `CACompromise`
    - Implied by `-crl_CA_compromise YYYYMMDDHHMMSSZ`
- `affiliationChanged`
- `cessationOfOperation`
- `certificateHold`
    - Implied by `-crl_hold holdInstructionNone`
    - Implied by `-crl_hold holdInstructionCallIssuer`
    - Implied by `-crl_hold holdInstructionReject`
- `removeFromCRL`

```sh
REVOKE_SERIAL=ABCDEF1234567890ABCDEF1234567890ABCDEF1
```

=== "Block Device"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -passin "file:${YKPINPATH}/PIN" \
    -revoke "${CADATAPATH}/certs/${REVOKE_SERIAL}.pem" \
    -crl_reason "unspecified"
    ```

=== "KDBX Database"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -passin file:<(keyctl pipe $KEYID_YKPIN) \
    -revoke "${CADATAPATH}/certs/${REVOKE_SERIAL}.pem" \
    -crl_reason "unspecified"
    ```

!!! note
    If `keyCompromise`, `CACompromise`, or `certificateHold` is the reason, then
    the `-crl_reason` flag is not required as it is implied by the specific
    flags associated with those reason.

    For example, if an Issuing CA was compromised, the following command sets
    the CA certificate as revoked starting at `14 August 2024` at
    `16:44:12 UTC`.

    === "Block Device"

        ```sh
        openssl ca \
        -config $CADATAPATH/openssl.cnf \
        -engine pkcs11 \
        -keyform engine \
        -passin "file:${YKPINPATH}/PIN" \
        -revoke "${CADATAPATH}/certs/${REVOKE_SERIAL}.pem" \
        -crl_compromise 20240814164412Z
        ```

    === "KDBX Database"

        ```sh
        openssl ca \
        -config $CADATAPATH/openssl.cnf \
        -engine pkcs11 \
        -keyform engine \
        -passin file:<(keyctl pipe $KEYID_YKPIN) \
        -revoke "${CADATAPATH}/certs/${REVOKE_SERIAL}.pem" \
        -crl_compromise 20240814164412Z
        ```

When a certificate is revoked, immediately issue an updated CRL:

=== "Block Device"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -passin "file:${YKPINPATH}/PIN" \
    -gencrl \
    -out $CADATAPATH/crl/ca.crl.pem
    ```

=== "KDBX Database"

    ```sh
    openssl ca \
    -config $CADATAPATH/openssl.cnf \
    -engine pkcs11 \
    -keyform engine \
    -passin file:<(keyctl pipe $KEYID_YKPIN) \
    -gencrl \
    -out $CADATAPATH/crl/ca.crl.pem
    ```

Convert the CRL to DER-encoding for publishing:

```sh
openssl crl \
-outform DER \
-in $CADATAPATH/crl/ca.crl.pem \
-out $CADATAPATH/crl/ca.crl
```

### Publish Updated CRL

#### Manually Using Github Web

Make a copy of the DER-encoded CRL with the correct CDP file name:

```sh
cp $CADATAPATH/crl/ca.crl $CADATAPATH/crl/DoubleU_Root_CA_01.crl
```

In the CA Github repository, click the drop-down box, then `View all branches`.
In the top-right, click the green `New branch` button. Create a name for the
branch, for example `update-crl`, and ensure the source is the default branch.
Then click the green `Create new branch` button. Next, click the name of the new
branch from the list.

Click the name of the CRL (eg. `DoubleU_Root_CA_01.crl`). On the top-right,
click the three-dot (`...`) button, then click `Delete file`. Then click
`Commit changes...`.

Next, on the top-right, click the `Add file` drop-down, then click `Upload
files`. Drag and drop the file from `$CADATAPATH/crl/`, or click `choose your
files` and navigate to `$CADATAPATH/crl/` and select `DoubleU_Root_CA_01.crl`.
Then add a commit message and click `Commit changes`.

You will be returned to the default repository view of the new branch. There
will be a box above the file list that says `This branch is 2 commits ahead`. On
the right side of that message box, click the `Contribute` drop down and click
`Open pull request`.

Enter a title that is along the lines of `update crl`, then state what was
changed in the description. Now click `Create pull request`.

If you have permissions to merge the request, then click `Merge and close`.
Otherwise, contact whomever has permissions to review the pull request and merge
it.

#### Manually Using Git CLI

Clone the repository. We'll use `$HOME/Documents/ca` for the cloned directory:

```sh
mkdir $HOME/Documents/ca
```

```sh
cd $HOME/Documents/ca
```

```sh
git clone https://github.com/doubleu-labs/ca .
```

Create a new branch:

```sh
git checkout -b update-crl
```

Remove the old CRL:

```sh
git rm DoubleU_Root_CA_01.crl
```

Add the new CRL from `$CADATAPATH/crl`:

```sh
cp $CADATAPATH/crl/ca.crl $HOME/Documents/ca/DoubleU_Root_CA_01.crl
```

Add the file to staging, create a commit containing the updated file with a 
message, then push the changes to a new branch:

```sh
git add DoubleU_Root_CA_01.crl
```

```sh
git commit -m 'updated crl'
```

```sh
git push -u origin update-crl
```

In your browser, navigate to the Github repository, then from the branch
drop-down on the top left above the file list, click your new branch's name.

In the box above the file list, click the `Contribute` drop-down and click `Open
pull request`. Add a title and description outlining changes, then click `Create
pull request`.

If you have permissions to merge the request, then click `Merge and close`.
Otherwise, contact whomever has permissions to review the pull request and merge
it.

#### Using Github API

```sh
source $CADATAPATH/deploy.env
```

Defined a function that produced URL-safe Base64 strings:

```sh
b64url() {
    openssl enc -base64 -A | tr '+/' '-_' | tr -d '='
}
```

```sh
HEADER=$(echo -n '{"alg":"RS256","typ":"JWT"}' | b64url)
```

```sh
PAYLOAD=$(
    jq -Mjnc \
    --arg iat $(date -ud '60 seconds ago' +'%s') \
    --arg axp $(date -ud '10 minutes' +'%s') \
    --arg iss $DEPLOY_APP_ID \
    '{
        "iat": $iat,
        "exp": $exp,
        "iss": $iss
    }' | b64url
)
```

```sh
CONTENT=$(echo -n "${HEADER}.${PAYLOAD}")
```

=== "Block Device"

    ```sh
    SIGNATURE=$(
        OPENSSL_CONF=$CADATAPATH/pkcs11.cnf \
        openssl dgst \
        -engine pkcs11 \
        -keyform engine \
        -binary \
        -sha256 \
        -sign "pkcs11:id=%03;type=private" \
        -passin "file:${YKPINPATH}/PIN" | \
        <<< $CONTENT | b64url
    )
    ```

=== "KDBX Database"

    ```sh
    SIGNATURE=$(
        OPENSSL_CONF=$CADATAPATH/pkcs11.cnf \
        openssl dgst \
        -engine pkcs11 \
        -keyform engine \
        -binary \
        -sha256 \
        -sign "pkcs11:id=%03;type=private" \
        -passin file:<(keyctl pipe $KEYID_YKPIN) | \
        <<< $CONTENT | b64url
    )
    ```

```sh
JWT="${CONTENT}.${SIGNATURE}"
```

Get the `slug` name of the App from the API:

```sh
DEPLOY_APP_SLUG=$(
    curl -s -X GET \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $JWT" \
    https://api.github.com/app | \
    jq -r '.slug'
)
```

Get the App's repository installation ID:

```sh
INSTALLATION=$(
    curl -s -X GET \
    -H "Accept: appliction/vnd.github+json" \
    -H "Authorization: Bearer $JWT" \
    https://api.github.com/app/installations | \
    jq --arg app $DEPLOY_REPO_OWNER \
    -r '.[] | select(.account.login=="$app") | .id'
)
```

Now exchange the `Bearer` JWT for an access token:

```sh
ACCESS_TOKEN=$(
    curl -s -X POST \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $JWT" \
    "https://api.github.com/app/installations/${INSTALLATION_ID}/access_tokens" | \
    jq -r '.token'
)
```

Generate the full name of the repository:

```sh
DEPLOY_REPO="${DEPLOY_REPO_OWNER}/${DEPLOY_REPO_NAME}"
```

Get the `HEAD` SHA of the branch that the pull request will be made against:

```sh
HEAD_SHA=$(
    curl -s -X GET \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $ACCESS_TOKEN" \
    "https://api.github.com/repos/${DEPLOY_REPO}/git/ref/heads/${DEPLOY_REPO_BRANCH}" | \
    jq -r '.object.sha'
)
```

Set the pull request title, body, and branch name:

```sh
PR_TITLE="update certificate revocation list"
PR_BODY="deploy new crl to pages"
PR_BRANCH="${DEPLOY_APP_SLUG}/update-crl"
```

Create the branch that the CRL will be uploaded to:

```sh
curl -s -X POST \
-H "Authorization: token $ACCESS_TOKEN" \
"https://api.github.com/repos/${DEPLOY_REPO}/git/refs" \
-d "$(
    jq -nc \
    --arg sha $HEAD_SHA \
    --arg branch "refs/heads/$PR_BRANCH" \
    '{
        "ref": $branch,
        "sha": $sha
    }'
)"
```

Get the SHA for the existing CRL file:

```sh
CRL_SHA=$(
    curl -s -X GET \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: token $ACCESS_TOKEN" \
    "https://api.github.com/repos/${DEPLOY_REPO}/contents/${DEPLOY_CDP_FILE}?ref=${PR_BRANCH}" | \
    jq -r '.sha'
)
```

Update the existing file with the contents of the new CRL. Be sure to specify
the DER-encoded CRL and ***NOT*** the PEM-encoded file:

```sh
curl -s -X PUT \
-H "Authorization: token $ACCESS_TOKEN" \
"https://api.github.com/repos/${DEPLOY_REPO}/contents/${DEPLOY_CDP_FILE}" \
-d "$(
    jq -nc \
    --arg content "$(base64 -w0 $CADATAPATH/crl/ca.crl)" \
    --arg branch $PR_BRANCH \
    --arg sha $CRL_SHA \
    '{
        "message": "update crl",
        "branch": $branch,
        "content": $content,
        "sha": $sha
    }'
)"
```

Create the pull request: 

```sh
curl -s -X POST \
-H "Authorization: token $ACCESS_TOKEN" \
"https://api.github.com/repos/${DEPLOY_REPO}/pulls" \
-d "$(
    jq -nc \
    --arg title $PR_TITLE \
    --arg body $PR_BODY \
    --arg branch $PR_BRANCH \
    --arg base $DEPLOY_REPO_BRANCH \
    '{
        "title": $title,
        "body": $body,
        "head": $branch,
        "base": $base
    }'
)"
```
