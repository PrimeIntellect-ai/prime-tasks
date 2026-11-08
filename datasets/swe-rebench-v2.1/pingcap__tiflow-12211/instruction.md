TiCDC crashes when the ignore_insert_value_expr configuration is enabled for tables containing virtual columns.
### What did you do?

1. create a changefeed with config
```
[filter]
[[filter.event-filters]]
matcher = ["test.t100"]
ignore-insert-value-expr = "zzz = 2"
```

2. create table
```
CREATE TABLE t100 (
    id INT PRIMARY KEY AUTO_INCREMENT,
    name VARCHAR(50),
    price DECIMAL(10,2),
    quantity INT,
    total_price DECIMAL(10,2) AS (price * quantity) VIRTUAL,
    zzz INT
);
```

3. insert data
```
INSERT INTO t100 (name, price, quantity, zzz) VALUES ('desk', 19.99, 5, 100);
```

### What did you expect to see?

TiCDC run normally

### What did you see instead?

TiCDC crash with error:
```
panic: runtime error: index out of range [5] with length 5

goroutine 130939 [running]:
github.com/pingcap/tidb/pkg/util/chunk.Row.IsNull(...)
        github.com/pingcap/tidb@v1.1.0-beta.0.20241213034006-c7f1b95c537a/pkg/util/chunk/row.go:218
github.com/pingcap/tidb/pkg/expression.(*Column).EvalInt(0x6?, {0x588aae0, 0xc0047f8340}, {0xc0083cdf40?, 0x0?})
        github.com/pingcap/tidb@v1.1.0-beta.0.20241213034006-c7f1b95c537a/pkg/expression/column.go:441 +0x29a
github.com/pingcap/tidb/pkg/expression.CompareInt({0x588aae0, 0xc0047f8340}, {0x588a1a8, 0xc004014580}, {0x588a330, 0xc003de1200}, {0xc0083cdf40?, 0xc004014d10?}, {0xc0083cdf40, 0x0})
        github.com/pingcap/tidb@v1.1.0-beta.0.20241213034006-c7f1b95c537a/pkg/expression/builtin_compare.go:2880 +0x5c
github.com/pingcap/tidb/pkg/expression.(*builtinEQIntSig).evalInt(0x425a740?, {0xc0083cdf40?, 0xc004014d10?})
        github.com/pingcap/tidb@v1.1.0-beta.0.20241213034006-c7f1b95c537a/pkg/expression/builtin_compare.go:2381 +0x67
github.com/pingcap/tidb/pkg/expression.(*ScalarFunction).EvalInt(0xc000928d90, {0x588aae0, 0xc0047f8340}, {0xc0083cdf40?, 0x0?})
        github.com/pingcap/tidb@v1.1.0-beta.0.20241213034006-c7f1b95c537a/pkg/expression/scalar_function.go:457 +0x92
github.com/pingcap/tidb/pkg/expression.(*ScalarFunction).Eval(0xc000928d90, {0xc0083cdf40?, 0xc007e115a0?})
        github.com/pingcap/tidb@v1.1.0-beta.0.20241213034006-c7f1b95c537a/pkg/expression/scalar_function.go:413 +0x249
github.com/pingcap/tiflow/pkg/filter.(*dmlExprFilterRule).skipDMLByExpression(0xc0045ff560?, {0xc00567a300?, 0xc007d51960?, 0x9?}, {0x588a4b8, 0xc000928d90})
        github.com/pingcap/tiflow/pkg/filter/expr_filter.go:335 +0xb5
github.com/pingcap/tiflow/pkg/filter.(*dmlExprFilterRule).shouldSkipDML(0xc0045ff560, 0xc000d43ce0, {{0xc00567a300, 0x5, 0x5}, {0x0, 0x0, 0x0}}, 0xc003e40270)
        github.com/pingcap/tiflow/pkg/filter/expr_filter.go:282 +0x4aa
github.com/pingcap/tiflow/pkg/filter.(*dmlExprFilter).shouldSkipDML(0xc0047f8cc0?, 0xc000d43ce0, {{0xc00567a300, 0x5, 0x5}, {0x0, 0x0, 0x0}}, 0xc003e40270)
        github.com/pingcap/tiflow/pkg/filter/expr_filter.go:428 +0x14b
github.com/pingcap/tiflow/pkg/filter.(*filter).ShouldIgnoreDMLEvent(0xc0047f8cc0, 0xc000d43ce0, {{0xc00567a300, 0x5, 0x5}, {0x0, 0x0, 0x0}}, 0x0?)
        github.com/pingcap/tiflow/pkg/filter/filter.go:157 +0x106
github.com/pingcap/tiflow/cdc/entry.(*mounter).unmarshalAndMountRowChanged.func1(0xd309e5?, 0x6c, 0xc000928460, {0xc004bb3e99, 0xa, 0x2?}, 0xc003913b00, {0x65ec6e003a00009, 0x65ec6e003a0000a, 0x6c, ...})
        github.com/pingcap/tiflow/cdc/entry/mounter.go:193 +0x3e7
github.com/pingcap/tiflow/cdc/entry.(*mounter).unmarshalAndMountRowChanged(0xc003913b00, {0x57fd3f0, 0xc004bfe960}, 0xc000928460)
        github.com/pingcap/tiflow/cdc/entry/mounter.go:206 +0x46d
github.com/pingcap/tiflow/cdc/entry.(*mounter).DecodeEvent(0xc003913b00, {0x57fd3f0, 0xc004bfe960}, 0xc004e3bb90)
        github.com/pingcap/tiflow/cdc/entry/mounter.go:118 +0x5e
github.com/pingcap/tiflow/cdc/entry.(*mounterGroup).runWorker(0xc00131c6c0, {0x57fd3f0, 0xc004bfe960})
        github.com/pingcap/tiflow/cdc/entry/mounter_group.go:121 +0x138
github.com/pingcap/tiflow/cdc/entry.(*mounterGroup).Run.func2()
        github.com/pingcap/tiflow/cdc/entry/mounter_group.go:87 +0x25
golang.org/x/sync/errgroup.(*Group).Go.func1()
        golang.org/x/sync@v0.9.0/errgroup/errgroup.go:78 +0x56
created by golang.org/x/sync/errgroup.(*Group).Go in goroutine 130912
        golang.org/x/sync@v0.9.0/errgroup/errgroup.go:75 +0x96
panic: runtime error: index out of range [5] with length 5
```

### Versions of the cluster

Upstream TiDB cluster version (execute `SELECT tidb_version();` in a MySQL client):

```console
(paste TiDB cluster version here)
```

Upstream TiKV version (execute `tikv-server --version`):

```console
(paste TiKV version here)
```

TiCDC version (execute `cdc version`):

```console
(paste TiCDC version here)
```
