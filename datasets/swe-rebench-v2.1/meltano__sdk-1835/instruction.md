__filter__ of stream map breaks tap-postgres
### Singer SDK Version

2.19.1

### Is this a regression?

- [ ] Yes

### Python Version

3.10

### Bug scope

Mapping (stream maps, flattening, etc.)

### Operating System

MacOS

### Description

my setup looks like this:
```yaml
  extractors:
  - name: tap-postgres
    pip_url: git+https://github.com/MeltanoLabs/tap-postgres.git@5320d1fa47442466785f6821af3ebfbe3ebff327
    config:
      stream_maps:
        public-time_series_meta:
          __filter__: ts_id in config['allowed_id']
      stream_map_config:
        allowed_id:
          - 2364
          - 2363
    select:
      - public-time_series_meta.*
```

The catalog from the tap contains the following:
```json
{
      "tap_stream_id": "public-time_series_meta",
      "table_name": "time_series_meta",
      "replication_method": "",
      "key_properties": [
        "ts_id"
      ],
      "schema": {
        "properties": {
          "ts_id": {
            "type": [
              "integer"
            ]
          },
          "name": {
            "type": [
              "string",
              "null"
            ]
          },
          "region": {
            "type": [
              "string",
              "null"
            ]
          },
          "source": {
            "type": [
              "string",
              "null"
            ]
          },
          "refers_to": {
            "type": [
              "integer",
              "null"
            ]
          },
          "default_source": {
            "type": [
              "boolean",
              "null"
            ]
          },
          "frequency": {
            "type": [
              "string",
              "null"
            ]
          },
          "kwargs": {
            "type": [
              "string",
              "null"
            ]
          },
          "description": {
            "type": [
              "string",
              "null"
            ]
          },
          "unit": {
            "type": [
              "string",
              "null"
            ]
          },
          "method": {
            "type": [
              "string",
              "null"
            ]
          },
          "load_interval": {
            "type": [
              "string",
              "null"
            ]
          },
          "access": {
            "type": [
              "string",
              "null"
            ]
          },
          "orig_timezone": {
            "type": [
              "string",
              "null"
            ]
          }
        },
        "type": "object",
        "required": [
          "ts_id"
        ]
      }
```

but when I run `meltano invoke tap postgres` I get:
`singer_sdk.exceptions.StreamMapConfigError: Invalid key properties for 'public-time_series_meta': [ts_id]. Property 'ts_id' was not detected in schema.`

Running the same config in meltano-map-transformer works fine.

### Code

```python
-
```

### Additional contract requirements

- Running the tap in discovery mode (the `--discover` CLI flag) with the reported
  `stream_maps` / `stream_map_config` configuration must not raise
  `singer_sdk.exceptions.StreamMapConfigError`.
