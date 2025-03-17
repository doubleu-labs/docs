# Initial Deployment and Wrap Up

So now that the CA is set up and initialized, the only thing left is to deploy
the CA certificate and CRL to the Github repository and have pages build and
make them available.

After that, we'll just need to create an archive of the CA, secure the
`root-ca.kdbx` database, and finally clean up the `ca-bootstrap` environment.

## Deploy Initial Assets

Run the following script to deploy the CA certificate and CRL to your Github
repository:

```sh
./scripts/deploy.sh -all
```

This will create a branch owned by the Github App and copy the certificate and
CRL to it in seperate commits. Then, a Pull Request will be made by the App
which you can then merge with your own account.

Doing it this way presents greater control over the assets and provides a log
of when assets were changed.

## Archive CA

Now, create a `tar` archive of the CA. This will package the `ca`, `certs`,
`crl`, and`db` directories. The archive will also include the `kdbx` directory
with only the `yk-pin.kdbx` database, and the `scripts` directory with select
scripts that will be needed for future operation.

```sh
./scripts/archive.sh
```

A timestamped `tar` file will be created in the root of the `ca-bootstrap`
directory.

## Secure CA

Next is to store `kdbx/root-ca.kdbx` and the timestamped archive in secure
locations. This can be removable media, secure cloud storage, or any other
suitable medium, or any combination of.

You can also compress the archive if you wish since they compress fairly well.

If you're using GPG/PGP keys, then it may be a good idea to create a detached
signature of the timestamped archive.

!!! note
    If you compressed your archive, be sure to sign the compressed file and not
    the uncompressed file.

```sh
gpg --armor --detach-sign rootca_20250101T121520Z.tar
```

This will generate a `.tar.asc` file alongside the archive. Store this with the
archive wherever you decide to store it so that the archive's integrity can be
verified.

## Cleanup

With those steps out of the way, you can finally clean up the `ca-bootstrap`
environment:

!!! danger
    Make ***ABSOLUTELY SURE*** that your `root-ca.kdbx` database is securely
    stored elsewhere before running this script. If it's not, ***it will be
    deleted and will not be recoverable***.

```sh
./scripts/purge.sh
```

You should be left with only the archive and optionally the signature in the
`ca-bootstrap` directory. If you have these stored elsewhere (and you should at
this point), you can safely delete the entire `ca-bootstrap` directory if you
wish.

## Next

Check out [CA operation](./operation.md) to see how to work with the CA.
