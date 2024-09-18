# Publish Certificate and CRL

## Mount CA Data Directory

```sh
USERNAME=${USER:-$(id -un)}
GROUPID=$(id -g)
```

```sh
DEVICE=/dev/sdb
```

Create the `CADATA` partition mount point:

```sh
sudo mkdir -p /run/media/$USERNAME/CADATA
```

Mount partition(s):

=== "Block Device"

    ```sh
    sudo mount "${DEVICE}4" /run/media/$USERNAME/CADATA \
        -o uid=$USERNAME -o gid=$GROUPID
    ```

=== "KDBX Database"

    ```sh
    sudo mount "${DEVICE}1" /run/media/$USERNAME/CADATA \
        -o uid=$USERNAME -o gid=$GROUPID
    ```

Set the path variable to `CADATA` and be sure to export it:

```sh
export CADATAPATH=/run/media/$USERNAME/CADATA
```

## Manual Publishing

If you prefer to manually publish the files instead of using the API, then it's
pretty straight forward.

The Certificate and CRL files will need to be coppied so that the file names are
correct. Do not just rename the files as OpenSSL we return errors in the future
since it won't be able to find the files with the original name. Renaming the
files after upload will require additional commits.

```sh
cp $CADATAPATH/ca/ca.crt $CADATAPATH/ca/DoubleU_Root_CA_01.crt
```

```sh
cp $CADATAPATH/crl/ca.crl $CADATAPATH/crl/DoubleU_ROOT_CA_01.crl
```

Navigate to the CA repository in your browser.

If you have the permissions to push directly to the default branch, next to the
green `<> Code` button, click the `Add file`/`+` button, then select
`Upload files`.

Drag-and-drop `$CADATAPATH/ca/DoubleU_Root_CA_01.crt` and
`$CADATAPATH/crl/DoubleU_Root_CA_01.crl` into the box, or click `choose your
files` and select these files.

I recommend writing a short commit message related to this initial publishing of
these files.

If you have permissions to directly publish to the default branch, then click
the bubble next to `Commit directly to the [NAME] branch` and then click the
green button `Commit changes`.

If you do not have the permissions, then click the bubble next to `Create a
**new branch** for this commit and start a pull request`, enter a name for the
new branch describing initial the initial publishing, then click the green
button `Propose changes`. Someone with permissions will then need to merge the
Pull Request.

## Publish Using the Github API

### Load PIN

=== "Block Device"

    Create a mount point for the `YKPIN` partition:

    ```sh
    sudo mkdir -p /run/media/$USERNAME/YKPIN
    ```

    Mount the `YKPIN` partition:

    ```sh
    YKPIN_PART="${DEVICE}3"
    YKPIN_UUID="$(sudo cryptsetup luksUUID $YKPIN_PART)
    ```

    ```sh
    sudo cryptsetup open $YKPIN_PART --type=luks "luks-${YKPIN_UUID}"
    ```

    ```sh
    sudo mount "/dev/mapper/luks-${YKPIN_UUID}" /run/media/$USERNAME/YKPIN \
        -o uid=$USERNAME -o gid=$GROUPID
    ```

    Set the path variable for the `YKPIN` partition:

    ```sh
    YKPINPATH=/run/media/$USERNAME/YKPIN
    ```

=== "KDBX Database"

    Start a new keyring session:

    === "Default Shell"

        ```sh
        keyctl session
        ```

    === "Non-default Shell"

        ```sh
        SHELL=/bin/zsh keyctl session
        ```
    
    ```sh
    KEYID_YKPIN=$(
        keepassxc-cli attachment-export \
        --stdout \
        $CADATAPATH/yubikey.kdbx \
        yubikey \
        PIN | \
        keyctl padd user yk-pin @s
    )
    ```

### Get Access Token

```sh
source $CADATAPATH/deploy.env
```

Define a function that produces URL-safe Base64 strings:

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

### Create Pull Request

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
PR_TITLE="publish ca certificate and crl"
PR_BODY="deploy new certificate and crl to pages"
PR_BRANCH="${DEPLOY_APP_SLUG}/install-crt-crl"
```

Create the branch that the files will be uploaded to:

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

Upload the CA certificate to the new branch. Be sure to specify the DER-encoded
certificate and ***NOT*** the PEM-encoded file:

```sh
curl -s -X PUT \
-H "Authorization: token $ACCESS_TOKEN" \
"https://api.github.com/repos/${DEPLOY_REPO}/contents/${DEPLOY_AIA_FILE}" \
-d "$(
    jq -nc \
    --arg content "$(base64 -w0 $CADATAPATH/ca/ca.crt)" \
    --arg branch $PR_BRANCH \
    '{
        "message": "create certificate",
        "branch": $branch,
        "content": $content
    }'
)"
```

Upload the CRL to the new branch. Be sure to specify the DER-encoded certificate
and ***NOT*** the PEM-encoded file:

```sh
curl -s -X PUT \
-H "Authorization: token $ACCESS_TOKEN" \
"https://api.github.com/repos/${DEPLOY_REPO}/contents/${DEPLOY_CDP_FILE}" \
-d "$(
    jq -nc \
    --arg content "$(base64 -w0 $CADATAPATH/crl/ca.crl)" \
    --arg branch $PR_BRANCH \
    '{
        "message": "create crl",
        "branch": $branch,
        "content": $content
    }'
)"
```

Create a pull request against the `DEPLOY_REPO_BRANCH`:

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

All that's left to do is merge the pull request. When the files are merged,
Github Actions should build and publish the contents to Pages.

### Unload Secrets

=== "Block Device"

    ```sh
    sudo umount "${DEVICE}3"
    ```

    ```sh
    sudo cryptsetup close "luks-${YKPIN_UUID}"
    ```

=== "KDBX Database"

    ```sh
    exit
    ```

## Wrapping Up

The CA is now initialized. Partitions can now be unmounted:

=== "Block Device"

    ```sh
    sudo umount "${DEVICE}4"
    ```

=== "KDBX Database"

    ```sh
    sudo umount "${DEVICE}1"
    ```