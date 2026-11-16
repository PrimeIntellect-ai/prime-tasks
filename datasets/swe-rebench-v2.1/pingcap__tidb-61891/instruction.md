tidb_load_binding_timeout cannot rightly init the default value
## Bug Report

Please answer these questions before submitting your issue. Thanks!

### 1. Minimal reproduce step (Required)

As the log shows, The duration is ```4.8µs```. it is not expected. and the user doesn't update this value.

```
{"level":"WARN","time":"2025/06/18 21:54:59.873 +00:00","caller":"binding_cache.go:164","message":"failed to load binding from storage","category":"sql-bind","sqlDigest":"ef7f1cf1ec0c2e0891e40d26dbe1b95d9c517683663b8d0e035ab160126c4c63","error":"load bindings from storage timeout","errorVerbose":"load bindings from storage timeout
github.com/pingcap/tidb/pkg/bindinfo.(*globalBindingHandle).LoadBindingsFromStorage
\t/mnt/tidb/sql/pkg/bindinfo/global_handle.go:713
github.com/pingcap/tidb/pkg/bindinfo.(*fuzzyBindingCache).loadFromStore
\t/mnt/tidb/sql/pkg/bindinfo/binding_cache.go:162
github.com/pingcap/tidb/pkg/bindinfo.(*fuzzyBindingCache).FuzzyMatchingBinding
\t/mnt/tidb/sql/pkg/bindinfo/binding_cache.go:106
github.com/pingcap/tidb/pkg/bindinfo.(*globalBindingHandle).MatchGlobalBinding
\t/mnt/tidb/sql/pkg/bindinfo/global_handle.go:473
github.com/pingcap/tidb/pkg/bindinfo.matchSQLBinding
\t/mnt/tidb/sql/pkg/bindinfo/binding_match.go:89
github.com/pingcap/tidb/pkg/bindinfo.MatchSQLBinding
\t/mnt/tidb/sql/pkg/bindinfo/binding_match.go:53
github.com/pingcap/tidb/pkg/planner.Optimize
\t/mnt/tidb/sql/pkg/planner/optimize.go:220
github.com/pingcap/tidb/pkg/executor.(*Compiler).Compile
\t/mnt/tidb/sql/pkg/executor/compiler.go:104
github.com/pingcap/tidb/pkg/session.(*session).ExecuteStmt
\t/mnt/tidb/sql/pkg/session/session.go:2086
github.com/pingcap/tidb/pkg/server.(*TiDBContext).ExecuteStmt
\t/mnt/tidb/sql/pkg/server/driver_tidb.go:294
github.com/pingcap/tidb/pkg/server.(*clientConn).handleStmt
\t/mnt/tidb/sql/pkg/server/conn.go:2030
github.com/pingcap/tidb/pkg/server.(*clientConn).handleQuery
\t/mnt/tidb/sql/pkg/server/conn.go:1783
github.com/pingcap/tidb/pkg/server.(*clientConn).dispatch
\t/mnt/tidb/sql/pkg/server/conn.go:1357
github.com/pingcap/tidb/pkg/server.(*clientConn).Run
\t/mnt/tidb/sql/pkg/server/conn.go:1127
github.com/pingcap/tidb/pkg/server.(*Server).onConn
\t/mnt/tidb/sql/pkg/server/server.go:740
runtime.goexit
\t/usr/local/go/src/runtime/asm_amd64.s:1650","duration":"4.8µs"}
```

so I add a assert into the problem place and CI report the panic at here. This indicates that there indeed is an issue here.

<img width="924" alt="Image" src="https://github.com/user-attachments/assets/cf06401f-46c9-4b27-98b3-c6254faf7888" />


<!-- a step by step guide for reproducing the bug. -->

### 2. What did you expect to see? (Required)

### 3. What did you see instead (Required)

### 4. What is your TiDB version? (Required)

<!-- Paste the output of SELECT tidb_version() -->

### Additional contract requirements

- The default value of `tidb_load_binding_timeout` is 200 (milliseconds).
- Setting `tidb_load_binding_timeout` to 0 must not leave binding loads with a zero timeout. In that case the session's binding load timeout (`LoadBindingTimeout` in the session variables) must be the default of 200 milliseconds.
