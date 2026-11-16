trestle validate component-definitions incorrectly failing on port-ranges
## Describe the bug

After upgrading to trestle 3.0.1, a ComponentDefinition file that was valid under trestle 2.6.1 started to fail with messages about the `protocols -> port-ranges` `start` and `end` values not being valid dicts. They should be non-negative integers.

## To Reproduce

Steps to reproduce the behavior:

Attempt to validate this minimum reproduction case:

```json
{
  "component-definition": {
    "uuid": "e7ba3d37-2ba0-4db9-9cf8-f5ec1214ffd5",
    "metadata": {
      "title": "Generic component-definition created by trestle named replication.",
      "last-modified": "2024-06-11T21:16:49.175968+00:00",
      "version": "0.0.0",
      "oscal-version": "1.1.2"
    },
    "components": [
      {
        "uuid": "4cef9684-578e-460e-a2d1-6eb78b8a76ca",
        "type": "REPLACE_ME",
        "title": "REPLACE_ME",
        "description": "REPLACE_ME",
        "protocols": [
          {
            "uuid": "0130b4ef-4561-4363-bab5-1e20b9888e49",
            "name": "https",
            "title": "Transport Layer Security",
            "port-ranges": [
              {
                "start": 443,
                "end": 443,
                "transport": "TCP"
              }
            ]
          }
        ],
        "control-implementations": []
      }
    ]
  }
}
```

## Expected behavior

`trestle validate` should return `VALID`.

## Screenshots / Logs.

<img width="1242" alt="Screenshot 2024-06-11 at 5 40 29 PM" src="https://github.com/oscal-compass/compliance-trestle/assets/285842/41618055-6437-4179-92d1-0ff322c82ddb">

## Environment

- OS: docker - python:3.11.9-slim base image.
- Python version: 3.11.9
- Installed packages: just trestle 3.0.1

### Additional contract requirements

- The public model `PortRange` in `trestle/oscal/common.py` accepts `start` and `end` as non-negative integers (a value below zero is rejected) and an optional `transport` of type `PortRangeValidValues` (for example `TCP` or `UDP`).
- The public model `AtFrequency` in `trestle/oscal/common.py` requires a `period` that is a positive integer (a `period` below 1 is rejected) and a required `unit` of type `TimeUnitValidValues`.
