Calling a plugin multiple times caches the first result
If a plugin backend has 2 entries in the hiera.yaml then lookups from the second one fail

hiera.yaml

```yaml
version: 5
hierarchy:
  - name: one
    data_hash: terraform_backend
    options:
      backend: local
      config:
        path: C:\Temp\hiera\one.tfstate
  - name: two
    data_hash: terraform_backend
    options:
      backend: local
      config:
        path: C:\Temp\hiera\two.tfstate
```

one.tfstate

```json
{
  "version": 3,
  "serial": 1,
  "modules": [
    {
      "path": [
        "root"
      ],
      "outputs": {
        "one": {
          "sensitive": false,
          "type": "string",
          "value": "one"
        }
      },
      "resources": {},
      "depends_on": []
    }
  ]
}
```

two.tfstate

```json
{
  "version": 3,
  "serial": 1,
  "modules": [
    {
      "path": [
        "root"
      ],
      "outputs": {
        "two": {
          "sensitive": false,
          "type": "string",
          "value": "two"
        }
      },
      "resources": {},
      "depends_on": []
    }
  ]
}
```

```
lookup.exe one
>one
lookup.exe two
>Error: lookup() did not find a value for the name 'two'
```
