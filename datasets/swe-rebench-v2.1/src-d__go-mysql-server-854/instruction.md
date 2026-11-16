Root opentracing span is not finished
The root opentracing span (https://github.com/src-d/go-mysql-server/blob/6f000e20fb418cf46eda4025c11ad26c5f0e4dc9/server/context.go#L97) which is created when serving queries via the SQL engine is never finished. When using jaeger, this results in traces with a name of `<trace-without-root-span>`.
