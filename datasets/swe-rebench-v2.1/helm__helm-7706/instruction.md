Fix output when --verify flag used
<!-- If you need help or think you have found a bug, please help us with your issue by entering the following information (otherwise you can delete this text): -->

Output of `helm version`: 3.1.0

Here's some example output...
```
$ helm pull --verify --keyring foo.pgp demo-repo/foo
Verification: &{0xc0008c80a0 sha256:f8a4e6e3ebf8a3fac95396b698f5517d43e0f5275bac3c484b6f38428b90b578 foo-0.1.0.tgz}
```

Don't think this is what we expect to see.

### Additional contract requirements

- For a successful `helm pull --verify` of the signed `signtest-0.1.0.tgz` test chart, the output must consist exactly of these lines, in this order:
```
Signed by: Helm Testing (This key should only be used for testing. DO NOT TRUST.) <helm-testing@helm.sh>
Using Key With Fingerprint: 5E615389B53CA37F0EE60BD3843BBF981FC18762
Chart Hash Verified: sha256:e5ef611620fb97704d8751c16bab17fedb68883bfb0edc76f78a70e9173f9b55
```
