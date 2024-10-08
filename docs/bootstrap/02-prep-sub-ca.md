# Prepare Subordinate/Issuing Certificate Authority

[Smallstep Certificates (Step CA)](https://github.com/smallstep/certificates) is
used as a subordinate / issuing / intermediate certificate authority for the
`home` subdomain.

In this environment, it will offer X.509 and SSH certificate authority services
as well as providing an ACME responder.

We're going to initialize this locally before starting any Lab OS installations
so that the CritiCluster nodes running Fedora CoreOS can be provided SSH
certificates and the Root CA certificate upon install via Ignition.

To achieve this, we're going to need container images for both `step-ca` and
`step-cli`, as well as PostgreSQL. We'll create a separate network for these
containers to run on so they can access eachother via container name.

```sh
podman pull \
docker.io/smallstep/step-{ca,cli}:latest \
docker.io/library/postgres:16
```

## Setup CA Working Directory

Ensure that the `LABBOOTSTRAPPATH` environment variable is set to the directory
you cloned [`doubleu-labs/bootstrap`](https://github.com/doubleu-labs/boostrap)
into.

In the `bootstrap` directory, there is directory called `.working` which
contains directories for `step-ca` and `step-client`. `step-ca` will contain, as
the name suggests, the CA data, while `step-client` will be the `$HOME`
directory while using the `step-cli` client container.

Set environment variables to the CA path:

```sh
STEPCAPATH=$LABBOOTSTRAPPATH/step-ca/ca
```

Create a directory in `STEPCAPATH` for certificates, password files, and
secrets:

```sh
mkdir $STEPCAPATH/passwords
```

## Generate Step CA Boilerplate

Create a dummy password file. The `password-file` and
`provisioner-password-file` flags are required to initialize the CA
non-interactively.

```sh
echo 'dummy' > $STEPCAPATH/passwords/dummy
```

Run `step ca init` using the container. The TLS certificate securing the API
endpoint is generated on-the-fly when the CA is started, so the `dns` flags
populate the `dnsNames` list which the certificate is signed to be valid for.
The provisioner here is named `dummy` and the provisioner password is using the
dummy file because with `remote-management` enabled, no provisioners are
created in the configuration file. A default admin provisioner will be created
when the CA starts for the first time using the `intermediate_ca` private key
password. This default admin provisioner will be replaced.

```sh
podman run --rm -it \
--volume=$STEPCAPATH:/home/step \
--userns=keep-id \
docker.io/smallstep/step-ca:latest \
step ca init \
--deployment-type=standalone \
--remote-management \
--ssh \
--name=dummy \
--dns='step-ca' \
--address=':443' \
--password-file=/home/step/passwords/dummy \
--provisioner=dummy \
--provisioner-password-file=/home/step/passwords/dummy
```

Now, delete the files we don't need:

```sh
rm -rf $STEPCAPATH/{certs,passwords,secrets}/* $STEPCAPATH/db
```

## Generate CA CSR

First, we need to create a Certificate Signing Request (CSR) for the new
`intermediate_ca` certificate. We're going to use OpenSSL to create the CSR
instead of the Step CLI because the CSR will be signed by OpenSSL and CSRs
generated by the Step CLI has some differences in field formatting that can
cause issues. For example, some string fields in OpenSSL CSRs at of the type
`UTF8STRING`, whereas ***ALL*** string fields in Step CLI CSRs are
`PRINTABLESTRING`. If you've configured any field contraints/policies, then the
type differences will cause OpenSSL to reject and refuse to sign the CSR, even
if the field content is visually the same.

Create a configuration file for the request. This could be done inline, but it's
easier to make adjustements with a file than long commands:

```conf title="$STEPCAPATH/certs/intermediate_ca.conf"
[req]
prompt = no
distinguished_name = req_dn

[req_dn]
CN   = DoubleU Labs HOME Issuing CA 01
O    = DoubleU Labs
OU   = Home
C    = US
0.DC = codes
1.DC = doubleu
2.DC = home
```

Generate a new password for the Sub CA private key:

```sh
< /dev/urandom tr -cd '[:alnum:]_-' | head -c128 > $STEPCAPATH/passwords/x509_ca
```

Now generate a CSR for the Sub CA:

```sh
openssl req -new \
-newkey ec \
-pkeyopt ec_paramgen_curve:P-384 \
-out $STEPCAPATH/certs/intermediate_ca.csr \
-keyout $STEPCAPATH/secrets/intermediate_ca_key \
-passout "file:${STEPCAPATH}/passwords/x509_ca" \
-config $STEPCAPATH/certs/intermediate_ca.conf
```

Now sign `$STEPCAPATH/certs/intermediate_ca.csr` and return the certificate as
well as copy of the PEM-encoded Root CA certificate. ([Root CA Sign](./01-root-ca/operation.md#sign-certificate))

Note the names of the certificates once placed in the `$STEPCAPATH/certs`
directory, or (re)name them `$STEPCAPATH/certs/intermediate_ca.crt` and
`$STEPCAPATH/certs/root_ca.crt`.

## Preconfigure Step CA

We're going to use `jq` to modify the configuration file so we don't have to
manually. But, one drawback is that `jq` can't inline edit files, so we'll have
to rename it, then redirect the output of `jq` to the original file name.

```sh
mv $STEPCAPATH/config/ca.json $STEPCAPATH/config/ca.json.orig
```

```sh
jq '
    .insecureAddress = ":80" |
    .crl = {
        enabled: true,
        generateOnRevoke: true
    } |
    .db = {
        type: "postgresql",
        dataSource: "postgresql://step:step@step-db:5432/step"
    }
' $STEPCAPATH/config/ca.json.orig > $STEPCAPATH/config/ca.json
```

Now lets generate passwords for the SSH user and host CAs:

```sh
for f in ssh_host_ca ssh_user_ca; do
    < /dev/urandom tr -cd '[:alnum:]_-' | head -c128 \
    > $STEPCAPATH/passwords/$f
done
```

Now lets generate the Host and User EdDSA keys. The public keys should be moved
into the `$STEPCAPATH/certs` directory:

```sh
for t in host user; do
    ssh-keygen -t ed25519 -a 100 -C '' \
    -N $(cat "${STEPCAPATH}/passwords/ssh_${t}_ca") \
    -f "${STEPCAPATH}/secrets/ssh_${t}_ca_key"
    mv "${STEPCAPATH}/secrets/ssh_${t}_ca_key.pub" $STEPCAPATH/certs/
done
```

## Start Step CA

Create a Podman network:

```sh
podman network create step
```

Start a PostgreSQL container using `step` as the user, password, and database
names:

```sh
podman run --rm -d \
--network=step \
--name=step-db \
--env=POSTGRES_USER=step \
--env=POSTGRES_PASSWORD=step \
--env=POSTGRES_DB=step \
docker.io/library/postgres:16
```

Now start the Step CA container:

```sh
podman run --rm -d \
--network=step \
--name=step-ca \
--userns=keep-id \
--volume=$STEPCAPATH:/home/step:z \
docker.io/smallstep/step-ca:latest \
step-ca \
--password-file=/home/step/passwords/x509_ca \
--ssh-host-password-file=/home/step/passwords/ssh_host_ca \
--ssh-user-password-file=/home/step/passwords/ssh_user_ca \
/home/step/config/ca.json
```

## Start Step CLI Client

```sh
STEPCLIENTPATH=$LABBOOTSTRAPPATH/step-ca/client
```

Make a separate directory for provisioner password files:

```sh
mkdir $STEPCAPATH/passwords/provisioners
```

We need to mount the `x509_ca` password file because the default `Admin JWK`
provisioner that is generated uses the CA key password file.

```sh
podman run --rm -it \
--network=step \
--userns=keep-id \
--volume=$STEPCLIENTPATH:/home/step:z \
--volume=$STEPCAPATH/passwords/provisioners:/passwords/provisioners:z \
--volume=$STEPCAPATH/passwords/x509_ca:/passwords/x509_ca:z \
--volume=$LABBOOTSTRAPPATH/step-ca/templates:/templates:z \
docker.io/smallstep/step-cli:latest
```

Now bootstrap the client. We need the fingerprint of the Root CA certificate, so
we'll use `curl` to get the PEM file and feed it to `step` to get that:

```sh
step ca bootstrap \
--ca-url=https://step-ca \
--fingerprint=$(
    step certificate fingerprint <(curl -sk https://step-ca/roots.pem)
)
```

The check that everything is working, execute the following:

```sh
step ca health
```

You should simply see `ok` printed to the console.

## Create New Admin Provisioner

By default, a provisioner named `Admin JWK` is created and is the provisioner
for the administrator called `step`. The password for `Admin JWK` is the
password for the CA's private key, so that needs to be changed.

There are two different types of administrators:

- `ADMIN`: Can manage provisioners
- `SUPER_ADMIN`: Can manage admins and provisioners

With this in mind, we're going to create one super admin and one admin
provisioner, this way we can stick to the principal of least privilege.

Create a password for the super admin provisioner:

```sh
step crypto rand --format=alphanumeric 128 \
> /passwords/provisioners/sadmin_home.doubleu.codes
```

Now create the super admin JWK provisioner:

```sh
step ca provisioner add sadmin@home.doubleu.codes --type=JWK --create \
--ssh=false \
--password-file=/passwords/provisioners/sadmin_home.doubleu.codes \
--admin-subject=step \
--admin-provisioner='Admin JWK' \
--admin-password-file=/passwords/x509_ca
```

Create the super administrator using the super admin provisioner:

```sh
step ca admin add sadmin@home.doubleu.codes sadmin@home.doubleu.codes \
--super \
--admin-subject=step \
--admin-provisioner='Admin JWK' \
--admin-password-file=/passwords/x509_ca
```

Delete the default `step` super administrator:

```sh
step ca admin remove step \
--admin-subject=sadmin@home.doubleu.codes \
--admin-provisioner=sadmin@home.doubleu.codes \
--admin-password-file=/passwords/provisioners/sadmin_home.doubleu.codes
```

And finally, delete the default `Admin JWK` provisioner:

```sh
step ca provisioner remove 'Admin JWK' \
--admin-subject=sadmin@home.doubleu.codes \
--admin-provisioner=sadmin@home.doubleu.codes \
--admin-password-file=/passwords/provisioners/sadmin_home.doubleu.codes
```

Now let's create the regular admin provisioner. Generate a password for it:

```sh
step crypto rand --format=alphanumeric 128 \
> /passwords/provisioners/admin_home.doubleu.codes
```

Create the admin JWK provisioner:

```sh
step ca provisioner add admin@home.doubleu.codes --type=JWK --create \
--ssh=false \
--password-file=/passwords/provisioners/admin_home.doubleu.codes \
--admin-subject=sadmin@home.doubleu.codes \
--admin-provisioner=sadmin@home.doubleu.codes \
--admin-password-file=/passwords/provisioners/sadmin_home.doubleu.codes
```

Set this provisioner as a regular admin:

```sh
step ca admin add admin@home.doubleu.codes admin@home.doubleu.codes \
--admin-subject=sadmin@home.doubleu.codes \
--admin-provisioner=sadmin@home.doubleu.codes \
--admin-password-file=/passwords/provisioners/sadmin_home.doubleu.codes
```

Now list the provisioners:

```sh
step ca provisioner list
```

You should see only the newly created admin and super admin JWK provisioners.

## Create Service Provisioners

### ACME

We're creating an ACME provisioner for use with every server on the network that
can support it.

Generate the password:

```sh
step crypto rand --format=alphanumeric 128 \
> /passwords/provisioners/acme_home.doubleu.codes
```

Create the ACME provisioner:

```sh
step ca provisioner add acme@home.doubleu.codes --type=ACME --create \
--ssh=false \
--password-file=/passwords/provisioners/acme_home.doubleu.codes \
--admin-subject=admin@home.doubleu.codes \
--admin-provisioner=admin@home.doubleu.codes \
--admin-password-file=/passwords/provisioners/admin_home.doubleu.codes
```

### SSH

For SSH provisioners, we need two: one JWK, and one SSHPOP.

Here's a quick table of the capabilities of each:

| Type      | user-cert sign        | host-cert sign        | user-cert renew   | host-cert renew       | revoke                | rekey                 |
| :-:       | :-:                   | :-:                   | :-:               | :-:                   | :-:                   | :-:                   |
| JWK       | :white_check_mark:    | :white_check_mark:    | :x:               | :x:                   | :white_check_mark:    | :x:                   |
| SSHPOP    | :x:                   | :x:                   | :x:               | :white_check_mark:    | :white_check_mark:    | :white_check_mark:    |

!!! note
    No provisioner can renew SSH user certificates. Request a new certificate
    using the same key or a new one.

Create a password for the JWK provisioner:

```sh
step crypto rand --format=alphanumeric 128 \
> /passwords/provisioners/ssh_home.doubleu.codes
```

Create the JWK provisioner using the template from the bootstrap directory. This
template restricts signed certificates to RSA and Ed25519 key types:

```sh
step ca provisioner add ssh@home.doubleu.codes --type=JWK --create \
--ssh \
--password-file=/passwords/provisioners/ssh_home.doubleu.codes \
--ssh-template=/templates/template_ssh.tpl \
--admin-subject=admin@home.doubleu.codes \
--admin-provisioner=admin@home.doubleu.codes \
--admin-password-file=/passwords/provisioners/admin_home.doubleu.codes
```

Now create the SSHPOP provisioner. No password is needed here:

```sh
step ca provisioner add sshpop@home.doubleu.codes --type=SSHPOP --create \
--admin-subject=admin@home.doubleu.codes \
--admin-provisioner=admin@home.doubleu.codes \
--admin-password-file=/passwords/provisioners/admin_home.doubleu.codes
```

### Issuer

This provisioner will be used for servers that cannot use ACME to get
certificates and instead need to generate traditional CSRs and have them signed.

```sh
step crypto rand --format=alphanumeric 128 \
> /passwords/provisioners/issuer_home.doubleu.codes
```

We're going to set a provisioner-specific X509 template with associated data.
The template takes the raw subject provided by the CSR, so be sure to inspect it
carefully before signing with this provisioner.

Copy the template data file and modify it for your environment:

```sh
cp /templates/issuer_template_x509.data.tpl /template/issuer_template_x509.data
```

In this data file, there is a field for the CRL Distribution Point (CDP) and
Authority Information Access (AIA) URLs. For example, my environment would be
configured something like this:

```json title="/templates/issuer_template_x509.data"
{
    "AIA": "https://ca.home.doubleu.codes/intermediates.pem",
    "CDP": "http://ca.home.doubleu.codes/crl"
}
```

!!! note
    Even though the AIA URL must be accessible via HTTP to be RFC-compliant,
    Step CA does route the path to the certificate on its HTTP router. The CDP
    URL is however available on HTTP, so we'll point it to that to try and avoid
    as many problems as we can.

The maximum and default duration of certificates signed by this issuer will be
set to 9,528 hours, or 397 days. Modern browsers will reject certificates signed
after September 1, 2020 that have validity periods longer than 398 days, so the
duration here is set to 397 to allow some leway in time zones.

```sh
step ca provisioner add issuer@home.doubleu.codes --type=JWK --create \
--ssh=false \
--password-file=/passwords/provisioners/issuer_home.doubleu.codes \
--x509-template=/templates/issuer_template_x509.tpl \
--x509-template-data=/templates/issuer_template_x509.data \
--x509-max-dur='9528h' \
--x509-default-dur='9528h' \
--admin-subject=admin@home.doubleu.codes \
--admin-provisioner=admin@home.doubleu.codes \
--admin-password-file=/passwords/provisioners/admin_home.doubleu.codes
```

### CritiCluster Step-Issuer

This issuer will be used in the CritiCluster K3s cluster to issuer certificates
for some internal service communication as well as securing services not behind
a terminating proxy.

```sh
step crypto rand --format=alphanumeric 128 \
> /passwords/provisioners/criticluster.step-issuer_home.doubleu.codes
```

```sh
step ca provisioner add criticluster.step-issuer@home.doubleu.codes \
--type=JWK \
--create \
--password-file=/passwords/provisioners/criticluster.step-issuer_home.doubleu.codes \
--admin-subject=admin@home.doubleu.codes \
--admin-provisioner=admin@home.doubleu.codes \
--admin-password-file=/passwords/provisioners/admin_home.doubleu.codes
```

### Export Provisioners

Some of the provisioner IDs will need to be referenced when building the
CritiCluster, so we'll export the full list of provisioners to a JSON file that
we can later parse with `jq`.

```sh
step ca provisioner list > $HOME/provisioners.json
```

## Create CritiCluster SSH Certificates

```sh
mkdir -p /home/step/ssh/criticluster0{1..3}
```

Each server will use RSA4096 and Ed25519 host keys. Both keys will include
principals for the hostname, FQDN, and IP address so that the certificate is
valid when connecting using any of these.

### CritiCluster01

```sh
step ssh certificate --host --kty=RSA --size=4096 criticluster01 \
/home/step/ssh/criticluster01/ssh_host_rsa_key \
--insecure \
--no-password \
--principal=criticluster01 \
--principal=criticluster01.home.doubleu.codes \
--principal=10.0.2.10 \
--provisioner=ssh@home.doubleu.codes \
--provisioner-password-file=/passwords/provisioners/ssh_home.doubleu.codes
```

```sh
step ssh certificate --host --kty=OKP --curve=Ed25519 criticluster01 \
/home/step/ssh/criticluster01/ssh_host_ed25519_key \
--insecure \
--no-password \
--principal=criticluster01 \
--principal=criticluster01.home.doubleu.codes \
--principal=10.0.2.10 \
--provisioner=ssh@home.doubleu.codes \
--provisioner-password-file=/passwords/provisioners/ssh_home.doubleu.codes
```

### CritiCluster02

```sh
step ssh certificate --host --kty=RSA --size=4096 criticluster02 \
/home/step/ssh/criticluster02/ssh_host_rsa_key \
--insecure \
--no-password \
--principal=criticluster02 \
--principal=criticluster02.home.doubleu.codes \
--principal=10.0.2.11 \
--provisioner=ssh@home.doubleu.codes \
--provisioner-password-file=/passwords/provisioners/ssh_home.doubleu.codes
```

```sh
step ssh certificate --host --kty=OKP --curve=Ed25519 criticluster02 \
/home/step/ssh/criticluster02/ssh_host_ed25519_key \
--insecure \
--no-password \
--principal=criticluster02 \
--principal=criticluster02.home.doubleu.codes \
--principal=10.0.2.11 \
--provisioner=ssh@home.doubleu.codes \
--provisioner-password-file=/passwords/provisioners/ssh_home.doubleu.codes
```

### CritiCluster03

```sh
step ssh certificate --host --kty=RSA --size=4096 criticluster03 \
/home/step/ssh/criticluster03/ssh_host_rsa_key \
--insecure \
--no-password \
--principal=criticluster03 \
--principal=criticluster03.home.doubleu.codes \
--principal=10.0.2.12 \
--provisioner=ssh@home.doubleu.codes \
--provisioner-password-file=/passwords/provisioners/ssh_home.doubleu.codes
```

```sh
step ssh certificate --host --kty=OKP --curve=Ed25519 criticluster03 \
/home/step/ssh/criticluster03/ssh_host_ed25519_key \
--insecure \
--no-password \
--principal=criticluster03 \
--principal=criticluster03.home.doubleu.codes \
--principal=10.0.2.12 \
--provisioner=ssh@home.doubleu.codes \
--provisioner-password-file=/passwords/provisioners/ssh_home.doubleu.codes
```

## Export and Wrap Up

Exit the client and shutdown the CA:

```sh
exit
```

```sh
podman stop step-ca
```

Dump the PostgreSQL database:

```sh
podman exec step-db pg_dump -U step step > $STEPCAPATH/dump.sql
```

Now the database container can be stopped and removed:

```sh
podman stop step-db
```

And the network can also be removed:

```sh
podman network rm step
```

Finally, we need to modify the `$STEPCAPATH/config/ca.json` file to set the
final `dnsNames` that the server will respond to, as well as changing the
database connection string:

Move the CA config so we can write it with 'jq' back to the original location:

```sh
mv $STEPCAPATH/config/ca.json $STEPCAPATH/config/ca.json.orig
```

Set the `dnsNames` and database `dataSource`:

```sh
jq '
    .dnsNames=[
        "127.0.0.1",
        "10.0.0.12",
        "ca.home.doubleu.codes",
        "step-ca.ca.svc.cluster.local"
    ] |
    .db.dataSource="postgresql://step@postgres-rw.cnpg-system.svc.cluster.local:5432/step"
' $STEPCAPATH/config/ca.json.orig > $STEPCAPATH/config/ca.json
```
