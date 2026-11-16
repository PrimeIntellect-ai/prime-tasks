Poor Error handling in package internal/certs
**Describe the bug**
The `certs.GenerateSecret` function takes arguments for the properties of a TLS Certificate to generate, including a CA Secret, and returns just a resuling Secret containing the new TLS Certificate. It is not reasonable to expect this operation to always succeed, and we should return an error and handle it appropriately at the caller.

In many cases this function will `log.Fatal` - which will cause the controller to exit.

**Example**
* create a secret in a namesapce with a running skupper Site containing anything but a valid TLS credentials `kubectl create secret generic invalid-ca --from-literal=tls.crt=not --from-literal=tls.key=valid`
* create a v2alpha1.Certificate resource referencing that secret as a ca.
```
cat << EOF | kubectl apply -f -
apiVersion: skupper.io/v2alpha1
kind: Certificate
metadata:
  name: my-site-server
spec:
  ca: invalid-ca
  hosts:
  - skupper-router
  - skupper-router.default
  - 172.18.255.113
  server: true
  subject: skupper-router
EOF
```
* See the skupper controller go into a crash loop.

### Additional contract requirements

When certificate generation fails because a referenced CA contains invalid credentials, the controller must handle the failure as a reconciliation error: it must remain running and report the certificate as not ready rather than terminate.
