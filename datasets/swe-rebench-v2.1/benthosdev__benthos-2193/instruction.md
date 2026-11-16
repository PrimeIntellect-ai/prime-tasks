parse_log processor returns structured data which isn't recognised by bloblang
The following config will print `unknown`:

```yaml
input:
  generate:
    count: 1
    mapping: |
        root = """<165>1 2003-10-11T22:14:15.003Z mymachine.example.com evntslog - ID47 [temp iut="3" eventSource="Application" eventID="1011"] BOMAn application event log entry..."""

pipeline:
  processors:
  - parse_log:
      format: syslog_rfc5424
      codec: json

  - mapping: |
      root = this.structureddata.type()
      # root = this.structureddata.string().parse_json().temp.eventID
```

As a workaround, one can use `.string().parse_json()` to extract subfields.

### Additional contract requirements

For RFC5424 messages, `structureddata` must be a Bloblang-recognized object. Its structured-data identifiers and parameters must be directly available as nested fields through Bloblang field navigation, without first stringifying and reparsing the value.
