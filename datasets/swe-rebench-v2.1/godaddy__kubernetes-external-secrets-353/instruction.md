Support `isBinary: true` for GCP secrets manager
This is useful if you have a secret (for example a JSON file) that is already base64 encoded in GCP secrets manager.

With this I can then create a secret that looks like

```data:
  credentials.json: |
  { ...}
```

which is needed e.g. when writing out GCP SA files.
