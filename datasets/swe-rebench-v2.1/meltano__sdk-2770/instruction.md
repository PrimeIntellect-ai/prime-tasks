bug: `table-key-properties` in `metadata` extra does not populate schema `key_properties` for `tap-bigquery`
### Singer SDK Version

0.39.1

### Is this a regression?

- [ ] Yes

### Python Version

3.9

### Bug scope

Taps (catalog, state, etc.)

### Operating System

Ubuntu 22.04 LTS

### Description

I've been trying to use `table-key-properties` to configure key properties for a BigQuery stream:

```yml
plugins:
  extractors:
  - name: tap-bigquery
    variant: meltanolabs
    pip_url: git+https://github.com/Matatika/tap-bigquery.git
    metadata:
      '*-events_*':
        table-key-properties:
        - event_timestamp
        - event_name
        - event_bundle_sequence_id
```

In this case, `key_properties` is empty so  when loading to a database target no primary keys are configured:

<details>
<summary>Generated catalog</summary>

```json
{
  "streams": [
    {
      "tap_stream_id": "analytics_376142012-events_20240825",
      "table_name": "events_20240825",
      "replication_method": "",
      "key_properties": [],
      "schema": ...,
      "is_view": false,
      "stream": "analytics_376142012-events_20240825",
      "metadata": [
        ...,
        {
          "breadcrumb": [],
          "metadata": {
            "inclusion": "available",
            "table-key-properties": [
              "event_timestamp",
              "event_name",
              "event_bundle_sequence_id"
            ],
            "forced-replication-method": "",
            "schema-name": "analytics_376142012",
            "selected": true
          }
        },
        ...
      ],
      "selected": true,
      "table_key_properties": [
        "event_timestamp",
        "event_name",
        "event_bundle_sequence_id"
      ]
    }
  ]
}
```

</details>

Primary keys are configured when using `key-properties`/`key_properties` (not documented [here](https://hub.meltano.com/singer/spec/#metadata)):

```yml
    metadata:
      '*-events_*':
        key-properties:
        - event_timestamp
        - event_name
        - event_bundle_sequence_id
```

<details>
<summary>Generated catalog</summary>

```json
{
  "streams": [
    {
      "tap_stream_id": "analytics_376142012-events_20240825",
      "table_name": "events_20240825",
      "replication_method": "",
      "key_properties": [
        "event_timestamp",
        "event_name",
        "event_bundle_sequence_id"
      ],
      "schema": ...,
      "is_view": false,
      "stream": "analytics_376142012-events_20240825",
      "metadata": [
        ...,
        {
          "breadcrumb": [],
          "metadata": {
            "inclusion": "available",
            "table-key-properties": [],
            "forced-replication-method": "",
            "schema-name": "analytics_376142012",
            "selected": true,
            "key-properties": [
              "event_timestamp",
              "event_name",
              "event_bundle_sequence_id"
            ]
          }
        },
        ...
      ],
      "selected": true
    }
  ]
}
```

</details>

```yml
    metadata:
      '*-events_*':
        key_properties:
        - event_timestamp
        - event_name
        - event_bundle_sequence_id
```

<details>
<summary>Generated catalog</summary>

```json
{
  "streams": [
    {
      "tap_stream_id": "analytics_376142012-events_20240825",
      "table_name": "events_20240825",
      "replication_method": "",
      "key_properties": [
        "event_timestamp",
        "event_name",
        "event_bundle_sequence_id"
      ],
      "schema": ...,
      "is_view": false,
      "stream": "analytics_376142012-events_20240825",
      "metadata": [
        ...,
        {
          "breadcrumb": [],
          "metadata": {
            "inclusion": "available",
            "table-key-properties": [],
            "forced-replication-method": "",
            "schema-name": "analytics_376142012",
            "selected": true,
            "key_properties": [
              "event_timestamp",
              "event_name",
              "event_bundle_sequence_id"
            ]
          }
        },
        ...
      ],
      "selected": true
    }
  ]
}
```

</details>

Why does this work? What is the correct way to do this? I assume `table-key-properties` is the intended approach, so I don't know if I'm going to run into some undefined behaviour down the line.

---

Related:
- https://discuss.meltano.com/t/16277188/hi-all-when-trying-to-specify-custom-pks-in-my-meltano-yml-b
- https://discuss.meltano.com/t/16276147/so-i-have-a-problem-i-need-to-replicate-table-from-postgres-
- https://discuss.meltano.com/t/16272691/need-advice-i-m-trying-to-develop-tap-bigquery-existing-from

### Code

_No response_

### Link to Slack/Linen

https://meltano.slack.com/archives/C069CQNHDNF/p1725976166433339
