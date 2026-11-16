Flaky unit test during CI
```
=== RUN   TestAggregationProjection
panic: runtime error: index out of range [2] with length 2

goroutine 286 [running]:
github.com/apache/arrow/go/v8/arrow/array.(*Binary).Value(...)
	/home/runner/go/pkg/mod/github.com/apache/arrow/go/v8@v8.0.1/arrow/array/binary.go:50
github.com/polarsignals/frostdb/query/physicalplan.hashBinaryArray(0xc0003fd3e0)
	/home/runner/work/frostdb/frostdb/query/physicalplan/aggregate.go:207 +0x475
github.com/polarsignals/frostdb/query/physicalplan.hashArray({0x150fec0?, 0xc0003fd3e0?})
	/home/runner/work/frostdb/frostdb/query/physicalplan/aggregate.go:193 +0x127
github.com/polarsignals/frostdb/query/physicalplan.(*HashAggregate).Callback(0xc0000dcfc0, {0x4aad25?, 0xde40b4?}, {0x1510b58, 0xc000152450})
	/home/runner/work/frostdb/frostdb/query/physicalplan/aggregate.go:290 +0xf70
github.com/polarsignals/frostdb/query/physicalplan.(*Synchronizer).Callback(0xc0003ed020, {0x15082e0, 0xc0001522d0}, {0x1510b58, 0xc000152450})
	/home/runner/work/frostdb/frostdb/query/physicalplan/synchronize.go:34 +0x10d
github.com/polarsignals/frostdb/query/physicalplan.(*HashAggregate).Finish(0xc0000dca20, {0x1508238, 0xc0002f4b80})
	/home/runner/work/frostdb/frostdb/query/physicalplan/aggregate.go:411 +0x924
github.com/polarsignals/frostdb/query/physicalplan.(*TableScan).Execute.func2()
	/home/runner/work/frostdb/frostdb/query/physicalplan/physicalplan.go:142 +0x62
golang.org/x/sync/errgroup.(*Group).Go.func1()
	/home/runner/go/pkg/mod/golang.org/x/sync@v0.0.0-20220601150217-0de741cfad7f/errgroup/errgroup.go:75 +0x87
created by golang.org/x/sync/errgroup.(*Group).Go
	/home/runner/go/pkg/mod/golang.org/x/sync@v0.0.0-20220601150217-0de741cfad7f/errgroup/errgroup.go:72 +0x12f
FAIL	github.com/polarsignals/frostdb	0.127s
```

### Additional contract requirements

- Appending a null binary entry followed by a non-null value must preserve both positions: the first entry is null and the following entry can be read with its original value.
- Processing binary-array values in an aggregation followed by a projection must complete without panicking.
