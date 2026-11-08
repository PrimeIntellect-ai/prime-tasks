[Issue] `v0.5.2`  breaks `regctl image inspect --format {{}}`
```console
❯ docker run --rm regclient/regctl:v0.5.1 image inspect regclient/regctl:latest --format '{{ jsonPretty .Config.Labels }}'
{
  "maintainer": "",
  "org.opencontainers.image.authors": "Regclient contributors",
  "org.opencontainers.image.created": "2023-09-27T19:49:08Z",
  "org.opencontainers.image.description": "",
  "org.opencontainers.image.documentation": "https://github.com/regclient/regclient",
  "org.opencontainers.image.licenses": "Apache 2.0",
  "org.opencontainers.image.revision": "56e0d20d046938b4bd9f24a780c4c6cdc2a4cfdf",
  "org.opencontainers.image.source": "https://github.com/regclient/regclient.git",
  "org.opencontainers.image.title": "regctl",
  "org.opencontainers.image.url": "https://github.com/regclient/regclient",
  "org.opencontainers.image.vendor": "",
  "org.opencontainers.image.version": "v0.5.2"
}

❯ docker run --rm regclient/regctl:v0.5.2 image inspect regclient/regctl:latest --format '{{ jsonPretty .Config.Labels }}'
template: out:1:21: executing "out" at <.Config.Labels>: can't evaluate field Config in type *blob.BOCIConfig
```
