Exec provider exception
**What happened (please include outputs or screenshots)**:
Exception in **config/exec_provider.py:run** if the console is not attached and sys.stdout is None (for example if compile binary with pyinstaller)
```
'NoneType' object has no attribute 'isatty'
```

**What you expected to happen**:
Exception is not happening

**How to reproduce it (as minimally and precisely as possible)**:
Use any config with exec, with any simple client, compile python to exe file with pyinstaller
```
apiVersion: v1
clusters:
- cluster:
    server: https://kube-oidc-proxy.lan
    insecure-skip-tls-verify: true
  name: default
contexts:
- context:
    cluster: default
    namespace: backend
    user: oidc
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: oidc
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1beta1
      args:
      - oidc-login
      - get-token
      - -v1
      - --oidc-issuer-url=https://some.lan/auth/realms/master
      - --oidc-client-id=kube-oidc-proxy
      - --oidc-client-secret=secret
      - --oidc-extra-scope=email
      - --grant-type=authcode
      - --authentication-timeout-sec=180
      command: kubectl
      env: null
      provideClusterInfo: false
```
This should call Popen inside exec_provider.py:run and open browser
```python
from kubernetes import client, config

# Configs can be set in Configuration class directly or using helper utility
config.load_kube_config()

v1 = client.CoreV1Api()
print("Listing pods with their IPs:")
ret = v1.list_pod_for_all_namespaces(watch=False)
for i in ret.items:
    print("%s\t%s\t%s" % (i.status.pod_ip, i.metadata.namespace, i.metadata.name))
```

**Anything else we need to know?**:
Suggested fix:
Changing this:
```python
    def run(self, previous_response=None):
        is_interactive = sys.stdout.isatty()
    ...
```
```python
    def run(self, previous_response=None):
       [HIDDEN]
   ...
```
Also Popen opens a 'shim' console window, which can be hidden with something like:
```python
startupinfo = None
if platform.system().lower() == 'windows':
    startupinfo = subprocess.STARTUPINFO()
    startupinfo.dwFlags = subprocess.CREATE_NEW_CONSOLE | subprocess.STARTF_USESHOWWINDOW
    startupinfo.wShowWindow = subprocess.SW_HIDE

process = subprocess.Popen(
    self.args,
    stdout=subprocess.PIPE,
    stderr=sys.stderr if is_interactive else subprocess.PIPE,
    stdin=sys.stdin if is_interactive else None,
    cwd=self.cwd,
    env=self.env,
    universal_newlines=True,
    startupinfo=startupinfo)
```
**Environment**:
- Kubernetes version: Client Version: v1.25.4, Kustomize Version: v4.5.7
- OS Windows: 11
- Python version: 3.10.9
- Python client version: 25.3.0

### Additional contract requirements

- When `sys.stdout` is `None`, running exec authentication must not raise an exception merely because stdout is unavailable while determining whether execution is interactive.
