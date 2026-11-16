Complex attributes must be allowed for LogRecord
Log data model (unlike traces and metrics) allows complex attribute values, non-homogeneous arrays, nested maps: https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/logs/data-model.md#type-any

The current implementation disallows such values, but should not.

**Steps to reproduce**
Use this code to create a log record:
```php
$record = (new LogRecord(['foo' => 'bar', 'baz' => 'bat', 'msg' => 'hello world']))
    ->setSeverityText('INFO')
    ->setSeverityNumber(9)
    ->setAttributes(['attr1' => 'val1','attr2' => 123, 'arrnum' => [1,2,3], 'complex' => [1, 'a'], 'nested' => [123, 'abc', ['sub'=>'val']]]);

$logger->emit($record);
```

**What is the expected behavior?**
All attributes should be output.

**What is the actual behavior?**
Complex attributes `complex` and `nested` are dropped:
```
                "attributes": {
                    "attr1": "val1",
                    "attr2": 123,
                    "arrnum": [
                        1,
                        2,
                        3
                    ]
                },
```

**Additional context**
Part of https://github.com/open-telemetry/community/issues/1537

### Additional contract requirements

Complex values are supported for log record attributes only. Trace and metric attributes must continue to reject nested maps and heterogeneous arrays.
