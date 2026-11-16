nsc import user does not expect a decorated jwt
When importing a system account using the procedure described [here](https://docs.nats.io/running-a-nats-service/nats_admin/security/jwt#import-operator-self-service) the final step fails.

```
root@clientk1:~# nsc import user --file system_user.jwt
[ERR ] failed to decode `system_user.jwt`: illegal base64 data at input byte 10
```

I was able to import the user by editing the jwt to remove the decoration line at the top and the corresponding line at the bottom of the file.  That is, remove the "-----BEGIN NATS ACCOUNT JWT-----".

```
root@clientk1:~# nsc import user --file system_user.jwt
[ OK ] user sys-non-op was successfully imported
```

Note that `nsc add operator` and `nsc import account` expect decorated JWTs.

Similar issues reported in #381 #499.  Apologies if this is fixed already.

nsc was installed using:

```
go install github.com/nats-io/nsc@latest
```
