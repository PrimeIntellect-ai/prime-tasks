No way to disable Jetstream from system account?
### What version were you using?

2.10.23

### What environment was the server running in?

Kubernetes

### Is this defect reproducible?

Yes

### Given the capability you are leveraging, describe your expectation?

Either not allow user to enable Jetstream in system account or allow Jetstream-enabled system account to disable it

### Given the expectation, what is the defect you are observing?

1. Without knowing system account shouldn't have Jetstream enabled, I enabled Jetstream
```
➜  nsc edit account SYS --js-enable=0
[ OK ] enabled global limit
[ OK ] edited account "SYS"
```
2. Once deployed the change, I see error message which makes me realize I shouldn't have enabled Jetstream:
```
[87] 2024/12/21 01:02:34.571811 [FTL] Not allowed to enable JetStream on the system account
```
3. Then I thought this is how to disable Jetstream, but turns out it isn't
```
➜  nsc edit account SYS --js-enable=1
[ OK ] enabled tier limit R1
[ OK ] edited account "SYS"
```
4. Then I tried to use `--js-disable` to disable Jetstream, but not able to:
```
➜  nsc edit account SYS --js-disable
Error: system account cannot have JetStream limits - please rerun with --js-disable
➜  nsc edit account SYS --js-disable
Error: system account cannot have JetStream limits - please rerun with --js-disable
```
5. Figured maybe I should remove the tier, but not able to:
```
➜  nsc edit account --rm-js-tier 0
Error: system account cannot have JetStream limits - please rerun with --js-disable
```
