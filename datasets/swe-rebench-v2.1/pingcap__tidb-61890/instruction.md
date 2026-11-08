`initGlobalVariableIfNotExists` [HIDDEN]
## Bug Report

Please answer these questions before submitting your issue. Thanks!

### 1. Minimal reproduce step (Required)

<!-- a step by step guide for reproducing the bug. -->

https://github.com/pingcap/tidb/blob/c597cb5e0a290153916d52a5600c7ee4b30c634a/pkg/session/bootstrap.go#L1043-L1058

### 2. What did you expect to see? (Required)

[HIDDEN]

### 3. What did you see instead (Required)

forget call it and caused some states of `s` to not be cleaned up.

If `mysql.GLOBAL_VARIABLES` has a clustered index, it will report an error log like

```
[2025/06/20 16:07:36.838 +08:00] [FATAL] [bootstrap.go:3591] ["mustExecute error"] [error="try to commit with invalid txnStartTS: 18446744073709551615"] [stack="github.com/pingcap/tidb/pkg/session.mustExecute\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/bootstrap.go:3591\ngithub.com/pingcap/tidb/pkg/session.initGlobalVariableIfNotExists\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/bootstrap.go:3327\ngithub.com/pingcap/tidb/pkg/session.upgradeToVer209\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/bootstrap.go:3181\ngithub.com/pingcap/tidb/pkg/session.upgrade\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/bootstrap.go:1556\ngithub.com/pingcap/tidb/pkg/session.runInBootstrapSession\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/session.go:3732\ngithub.com/pingcap/tidb/pkg/session.bootstrapSessionImpl\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/session.go:3458\ngithub.com/pingcap/tidb/pkg/session.BootstrapSession\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/session.go:3404\nmain.createStoreDDLOwnerMgrAndDomain\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/cmd/tidb-server/main.go:416\nmain.main\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/cmd/tidb-server/main.go:320\nruntime.main\n\t/Users/pingcap/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.23.6.darwin-arm64/src/runtime/proc.go:272"] [stack="github.com/pingcap/tidb/pkg/session.mustExecute\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/bootstrap.go:3591\ngithub.com/pingcap/tidb/pkg/session.initGlobalVariableIfNotExists\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/bootstrap.go:3327\ngithub.com/pingcap/tidb/pkg/session.upgradeToVer209\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/bootstrap.go:3181\ngithub.com/pingcap/tidb/pkg/session.upgrade\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/bootstrap.go:1556\ngithub.com/pingcap/tidb/pkg/session.runInBootstrapSession\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/session.go:3732\ngithub.com/pingcap/tidb/pkg/session.bootstrapSessionImpl\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/session.go:3458\ngithub.com/pingcap/tidb/pkg/session.BootstrapSession\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/pkg/session/session.go:3404\nmain.createStoreDDLOwnerMgrAndDomain\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/cmd/tidb-server/main.go:416\nmain.main\n\t/Users/pingcap/workspace/bp-tidb-release-darwin-arm64-w2tsl-build-binaries/source/tidb/cmd/tidb-server/main.go:320\nruntime.main\n\t/Users/pingcap/go/pkg/mod/golang.org/toolchain@v0.0.1-go1.23.6.darwin-arm64/src/runtime/proc.go:272"]
```

### 4. What is your TiDB version? (Required)

<!-- Paste the output of SELECT tidb_version() -->
v8.5.2, master

### Additional contract requirements

- The query result used during global-variable initialization must be cleaned up on every exit path, so it does not leave session state uncleaned or interfere with subsequent work.
