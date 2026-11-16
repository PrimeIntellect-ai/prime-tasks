helm push using zot is 403
<!-- If you need help or think you have found a bug, please help us with your issue by entering the following information (otherwise you can delete this text): -->

Output of `helm version`:
version.BuildInfo{Version:"v3.12.0", GitCommit:"c9f554d75773799f72ceef38c51210f1842a1dea", GitTreeState:"clean", GoVersion:"go1.20.3"}
Output of `kubectl version`:

Cloud Provider/Platform (AKS, GKE, Minikube etc.):

1. login
```
helm registry login 192.168.64.1:6000 --username admin --insecure --password admin --debug
WARNING: Using --password via the CLI is insecure. Use --password-stdin.
Login Succeeded
```
2. push
```
helm  push openebs-3.4.1.tgz   oci://192.168.64.1:6000/charts --insecure-skip-tls-verify
Error: unexpected status from POST request to https://192.168.64.1:6000/v2/charts/openebs/blobs/uploads/: 403 Forbidden
```

so I  modify code

```
if client.resolver == nil {
		[HIDDEN]
		[HIDDEN]

		[HIDDEN]
		if err != nil {
			return nil, err
		}
		client.resolver = resolver
	}
```

Upload was successful. I think it's an oci upload error. We need to upgrade the code to support it. If you agree with me, you can assign this issue to me.

### Additional contract requirements

- After a successful login to an OCI registry, a subsequent Helm push to that registry must use the credentials established by the login for registry requests requiring authentication and complete successfully.
