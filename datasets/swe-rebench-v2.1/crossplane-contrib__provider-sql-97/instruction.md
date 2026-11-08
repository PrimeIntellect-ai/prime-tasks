GRANTs Failing for Several Grant Types
### What happened?
I'm attempting to create several GRANTs in MySQL. A few succeed, but several fail with `cannot create grant: Error 1221: Incorrect usage of DB GRANT and GLOBAL PRIVILEGES`. It seems to be related to the specific GRANT types I am trying to create.

`PROCESS, REPLICATION CLIENT, REPLICATION SLAVE` in particular.

I can create the failing GRANTs from the MySQL CLI without any issue, using the same username/password that Crossplane is using.

Other GRANT objects with different sets of GRANT types work correctly and create the grants. e.g. `"SELECT","INSERT","UPDATE",
"DELETE","EXECUTE","CREATE TEMPORARY TABLES"`


```
NAME                                              READY   SYNCED   AGE    ROLE                DATABASE               PRIVILEGES
grant.mysql.sql.crossplane.io/datadog-perf        True    True     2d6h   datadog             performance_schema.*   ["SELECT"]
grant.mysql.sql.crossplane.io/datadog-repl        False   False    2d6h   datadog             *.*                    ["REPLICATION CLIENT","PROCE
SS"]
grant.mysql.sql.crossplane.io/somegrantfoo     True    True     2d7h   someuser     *.*                    ["SELECT","INSERT","UPDATE",
"DELETE","EXECUTE","CREATE TEMPORARY TABLES"]
```

### How can we reproduce it?
``` yaml
apiVersion: mysql.sql.crossplane.io/v1alpha1
kind: Grant
metadata:
  name: datadog-repl
spec:
  providerConfigRef:
    name: foo
  forProvider:
    privileges:
      - REPLICATION CLIENT
      - PROCESS
    userRef:
      name: datadog
    database: "*.*"
```

### What environment did it happen in?
Crossplane version:

`Image:         crossplane/crossplane:v1.7.0`
`Image:         crossplane/provider-sql-controller:v0.4.1`

* Cloud: Azure MySQL Flexible Server v8.0
* Kubernetes version:
``` sh
> kubectl version
Client Version: version.Info{Major:"1", Minor:"23", GitVersion:"v1.23.5", GitCommit:"c285e781331a3785a7f436042c65c5641ce8a9e9", GitTreeState:"clean", BuildDate:"2022-03-16T15:51:05Z", GoVersion:"go1.17.8", Compiler:"gc", Platform:"darwin/amd64"}
Server Version: version.Info{Major:"1", Minor:"22", GitVersion:"v1.22.6", GitCommit:"5963a7a5570a1b8c977c31ced503cb20f0ef6e8c", GitTreeState:"clean", BuildDate:"2022-03-10T07:59:42Z", GoVersion:"go1.16.12", Compiler:"gc", Platform:"linux/amd64"}
```
* Kubernetes distribution: Azure AKS
* OS (e.g. from /etc/os-release)
``` sh
> # cat /etc/os-release
NAME="Ubuntu"
VERSION="18.04.6 LTS (Bionic Beaver)"
```
* Kernel (e.g. `uname -a`)
``` sh
 uname -a
Linux aks-lab90-23705758-vmss000001 5.4.0-1069-azure #72~18.04.1-Ubuntu SMP Mon Feb 7 11:12:24 UTC 2022 x86_64 x86_64 x86_64 GNU/Linux
```

### Debug Log
```
provider-sql 2022-04-04T03:21:03.853Z	DEBUG	provider-sql	Cannot create external resource	{"controller": "managed/grant.mysql.sql.crossplane.io", "request": "/datadog-repl", "uid": "1a84a73b-e5d0-4958-92b1-07d82e0992b1", "version": "185563119", "external-name": "datadog-repl", "error": "cannot create grant: Error 1221: Incorrect usage of DB GRANT and GLOBAL PRIVILEGES", "errorVerbose": "Error 1221: Incorrect usage of DB GRANT and GLOBAL PRIVILEGES\ncannot create grant\ngithub.com/crossplane-contrib/provider-sql/pkg/controller/mysql/grant.(*external).Create\n\t/home/runner/work/provider-sql/provider-sql/pkg/controller/mysql/grant/reconciler.go:249\ngithub.com/crossplane/crossplane-runtime/pkg/reconciler/managed.(*Reconciler).Reconcile\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/github.com/crossplane/crossplane-runtime@v0.13.0/pkg/reconciler/managed/reconciler.go:670\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).reconcileHandler\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/sigs.k8s.io/controller-runtime@v0.8.0/pkg/internal/controller/controller.go:293\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).processNextWorkItem\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/sigs.k8s.io/controller-runtime@v0.8.0/pkg/internal/controller/controller.go:248\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Start.func1.1\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/sigs.k8s.io/controller-runtime@v0.8.0/pkg/internal/controller/controller.go:211\nk8s.io/apimachinery/pkg/util/wait.JitterUntilWithContext.func1\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/k8s.io/apimachinery@v0.20.1/pkg/util/wait/wait.go:185\nk8s.io/apimachinery/pkg/util/wait.BackoffUntil.func1\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/k8s.io/apimachinery@v0.20.1/pkg/util/wait/wait.go:155\nk8s.io/apimachinery/pkg/util/wait.BackoffUntil\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/k8s.io/apimachinery@v0.20.1/pkg/util/wait/wait.go:156\nk8s.io/apimachinery/pkg/util/wait.JitterUntil\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/k8s.io/apimachinery@v0.20.1/pkg/util/wait/wait.go:133\nk8s.io/apimachinery/pkg/util/wait.JitterUntilWithContext\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/k8s.io/apimachinery@v0.20.1/pkg/util/wait/wait.go:185\nk8s.io/apimachinery/pkg/util/wait.UntilWithContext\n\t/home/runner/work/provider-sql/provider-sql/.work/pkg/pkg/mod/k8s.io/apimachinery@v0.20.1/pkg/util/wait/wait.go:99\nruntime.goexit\n\t/opt/hostedtoolcache/go/1.17.7/x64/src/runtime/asm_amd64.s:1581"}
```

### Additional contract requirements

- The `database` and `table` fields of a MySQL `Grant` are optional and default to `*`. A grant that omits `database` and/or `table` therefore applies to the global scope; omitting both yields the `*.*` scope. Observing such a grant must not fail, and must report it as existing and up to date when the corresponding global grant (`GRANT ... ON *.* TO ...`) is present.
- Global-only MySQL privileges, including `PROCESS` and `REPLICATION CLIENT`, must be creatable on the global `*.*` scope.
