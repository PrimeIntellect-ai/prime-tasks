cdxgen does not follow CycloneDX 1.4 spec for SPDX license expressions
Per the [CycloneDX 1.4 Spec](https://cyclonedx.org/docs/1.4/json/#components_items_licenses_items_expression), SPDX expressions should be added under the licenses array as the `expression` object, not the `license` object. This requires the utility to match the input license against SPDX expressions and make the appropriate choice.

Current behavior:

`type-fest`:

```json
    {
      "group": "",
      "name": "type-fest",
      "version": "0.20.2",
      "hashes": [
        {
          "alg": "SHA-512",
          "content": "35ef9e138af4fe25a7a40c43f39db3dc0f8dd01b7944dfff36327045dd95147126af2c317f9bec66587847a962c65e81fb0cfff1dfa669348090dd452242372d"
        }
      ],
      "licenses": [
        {
          "license": {
            "name": "(MIT OR CC0-1.0)"
          }
        }
      ],
      "purl": "pkg:npm/type-fest@0.20.2",
      "type": "library",
      "bom-ref": "pkg:npm/type-fest@0.20.2",
      "properties": [
        {
          "name": "SrcFile",
          "value": "/app/package-lock.json"
        }
      ]
    },
```

Expected Behavior:

`type-fest`:
```json
    {
      "group": "",
      "name": "type-fest",
      "version": "0.20.2",
      "hashes": [
        {
          "alg": "SHA-512",
          "content": "35ef9e138af4fe25a7a40c43f39db3dc0f8dd01b7944dfff36327045dd95147126af2c317f9bec66587847a962c65e81fb0cfff1dfa669348090dd452242372d"
        }
      ],
      "licenses": [
        {
          "expression": "(MIT AND CC0-1.0)"
        }
      ],
      "purl": "pkg:npm/type-fest@0.20.2",
      "type": "library",
      "bom-ref": "pkg:npm/type-fest@0.20.2",
      "properties": [
        {
          "name": "SrcFile",
          "value": "/app/package-lock.json"
        }
      ]
    },
```

My example came from an npm package. The `license` field in package.json can be an SPDX expression.

`type-fest`:

```json
    "node_modules/serialize-error/node_modules/type-fest": {
      "version": "0.20.2",
      "resolved": "<url>",
      "integrity": "sha512-Ne+eE4r0/iWnpAxD852z3A+N0Bt5RN//NjJwRd2VFHEmrywxf5vsZlh4R6lixl6B+wz/8d+maTSAkN1FIkI3LQ==",
      "inBundle": true,
      "license": "(MIT OR CC0-1.0)",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
```

This issue may relate to https://github.com/CycloneDX/cdxgen/issues/41

### Additional contract requirements

When a package supplies an SPDX license expression, represent it in the licenses array as an `expression` value without changing its logical meaning. In the `type-fest` example above, the supplied expression uses `OR`, so the expression in the output must use `OR` as well; changing it to `AND` does not preserve the supplied license expression.
