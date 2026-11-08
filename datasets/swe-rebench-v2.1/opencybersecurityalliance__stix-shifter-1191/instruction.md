elastic_ecs MATCHES operator is translated incorrectly
**Describe the bug**
The MATCHES operator doesn't work with elastic_ecs at all.  I believe the problem is that the module uses Elasticsearch "query string" syntax (this doesn't appear to be documented anywhere however) and regular expressions should be wrapped in `/`s: https://www.elastic.co/guide/en/elasticsearch/reference/8.5/query-dsl-query-string-query.html#_regular_expressions

[HIDDEN]

**To Reproduce**
Try any pattern with MATCHES:
```$ stix-shifter translate elastic_ecs query '{}' "[process:name MATCHES '.*\\.exe']"
line 1:22 mismatched input ''' expecting StringLiteral
 2022-11-14 16:38:39,472 stix_shifter_modules.elastic_ecs.stix_translation.query_translator INFO     Converting STIX2 Pattern to data source query
{
    "queries": [
        "(process.name : .*\\\\.exe OR process.parent.name : .*\\\\.exe) AND (@timestamp:[\"2022-11-14T21:33:39.473Z\" TO \"2022-11-14T21:38:39.473Z\"])"
    ]
}

```

**Expected behavior**
The translated query should wrap the RE with forward slashes.

**Additional context**
```
$ pip list | grep stix-shifter
stix-shifter                      4.5.1
stix-shifter-modules-elastic-ecs  4.5.1
stix-shifter-modules-qradar       4.5.1
stix-shifter-modules-splunk       4.5.1
stix-shifter-utils                4.2.4
$ pip list | grep antlr
antlr4-python3-runtime            4.8
```

### Additional contract requirements

- For elastic_ecs, translate MATCHES regular-expression values as query-string regular expressions enclosed in forward slashes, preserving the regex content.
