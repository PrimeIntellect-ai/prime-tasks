Unmarshalling issues with some JSON responses in webhook provider
**Describe the bug**
ESO webhook provider "crashes" on strings with escaped forward slahes.

**To Reproduce**
I'm using ESO v0.9.4 with the webhook provider. I use it to extract an authentication token from VENAFI TPP.
I use a `ClusterSecretStore` like this one:
```
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: venafi-webhook-backend
spec:
  provider:
    webhook:
      body: '{"username":"{{ .auth.username }}","password":"{{ .auth.password }}","client_id":
        "My_Client_ID","scope":"configuration:manage,delete;certificate:manage"}'
      headers:
        Accept: application/json
        Content-Type: application/json
      method: POST
      result:
        jsonPath: $.access_token
      secrets:
      - name: auth
        secretRef:
          name: venafi-webhook-credentials
          namespace: co
      timeout: 1m
      url: https://cert-manager.adidas.com/vedauth/authorize/oauth
```

I detected VENAFI was issuing more authentication tokens than expected, so digging into the logs I saw:
```
{"level":"error","ts":1700746900.245956,"logger":"controllers.ExternalSecret","msg":"could not get secret data from provider","ExternalSecret":{"name":"venafi-webhook","namespace":"default"},"error":"failed to parse response json: yaml: found unknown escape character","stacktrace":"github.com/external-secrets/external-secrets/pkg/controllers/externalsecret.(*Reconciler).Reconcile\n\t/home/runner/work/external-secrets/external-secrets/pkg/controllers/externalsecret/externalsecret_controller.go:205\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Reconcile\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.15.1/pkg/internal/controller/controller.go:118\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).reconcileHandler\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.15.1/pkg/internal/controller/controller.go:314\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).processNextWorkItem\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.15.1/pkg/internal/controller/controller.go:265\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Start.func2.2\n\t/home/runner/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.15.1/pkg/internal/controller/controller.go:226"}
```

The issue I identified is that access or refresh tokens can arrive with an escaped forward slash, i.e.:
```
{"access_token":"REDACTED","refresh_token":"RE\/DACTED==","expires_in":86399,"expires":1700833565,"token_type":"Bearer","scope":"certificate:manage;configuration:delete,manage","identity":"AD+mydomain.com:a748392498bcb42323427ac392ff","refresh_until":1700833565}%
```

In such cases, the Unmarshall method fails and I see the aforementioned error: `failed to parse response json: yaml: found unknown escape character`. Because of this error, ESO assumes the request has failed and it enqueues it, leading to that increase of tokens issued. The valid token is the one without the backslash.

[HIDDEN]

(Ideally fixing VENAFI, but that also seems difficult)

WDYT?

**Expected behavior**
I expect to fetch correctly the access_token from that JSON.

### Additional contract requirements

The webhook must successfully extract the configured `access_token` from the described response even when another JSON string field contains an escaped forward slash. When the selected token string contains an escaped forward slash, the returned token must contain `/` without the escape backslash.
