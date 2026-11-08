The minvalue of the column statistic incorrectly ignores empty strings
Hi.
When I used the following statement `select from xxx where colume="-xxx"` to query, the written entries could not be queried. However, I changed it to `select from xxx where colume like "%-xxx"` and it could be queried. Finally, I found that this column recorded the wrong minimum value, which caused the query engine to skip the group when using =, while like is a global scan, so it can be found.

What ends up happening is that this code creates this bug

https://github.com/parquet-go/parquet-go/blob/main/writer.go#L1575
```
var existingMaxValue, existingMinValue Value

if c.columnChunk.MetaData.Statistics.MaxValue != nil && c.columnChunk.MetaData.Statistics.MinValue != nil {
        existingMaxValue = c.columnType.Kind().Value(c.columnChunk.MetaData.Statistics.MaxValue)
        existingMinValue = c.columnType.Kind().Value(c.columnChunk.MetaData.Statistics.MinValue)
}

if existingMaxValue.isNull() || c.columnType.Compare(maxValue, existingMaxValue) > 0 {
        buf := c.columnChunk.MetaData.Statistics.MaxValue[:0]
        c.columnChunk.MetaData.Statistics.MaxValue = maxValue.AppendBytes(buf)
}


if existingMinValue.isNull() || c.columnType.Compare(minValue, existingMinValue) < 0 {
        buf := c.columnChunk.MetaData.Statistics.MinValue[:0]
        [HIDDEN]
}
```

[HIDDEN] I only found that this is affected here, but I don’t know if there are similar problems elsewhere, so I am unable to fully fix this problem.

This is a very serious bug, which will cause the query engine to be unable to query data. Please fix this bug as quickly as possible!!!

Thank you so much !
