rootfilepath need a / after the base
according to https://github.com/solid/community-server/issues/444#issuecomment-751502319


i've tried a rootfilepath or more a "-f" but URL needs a / after the base
```
C:\Users\Smag\Documents\dev\community-server>npm start -- -p 5000 -c config/config-file.json -f data

> @solid/community-server@0.3.0 start C:\Users\Smag\Documents\dev\community-server
> node ./bin/server.js "-p" "5000" "-c" "config/config-file.json" "-f" "data"

2021-01-01T17:24:32.377Z [ExtensionBasedMapper] warn: URL http://localhost:5000 needs a / after the base
BadRequestHttpError: URL needs a / after the base

C:\Users\Smag\Documents\dev\community-server>npm start -- -p 5000 -c config/config-file.json -f data/

> @solid/community-server@0.3.0 start C:\Users\Smag\Documents\dev\community-server
> node ./bin/server.js "-p" "5000" "-c" "config/config-file.json" "-f" "data/"

2021-01-01T17:25:10.306Z [ExtensionBasedMapper] warn: URL http://localhost:5000 needs a / after the base
BadRequestHttpError: URL needs a / after the base

C:\Users\Smag\Documents\dev\community-server>npm start -- -p 5000 -c config/config-file.json -f /data/

> @solid/community-server@0.3.0 start C:\Users\Smag\Documents\dev\community-server
> node ./bin/server.js "-p" "5000" "-c" "config/config-file.json" "-f" "/data/"

2021-01-01T17:26:14.552Z [ExtensionBasedMapper] warn: URL http://localhost:5000 needs a / after the base
BadRequestHttpError: URL needs a / after the base

C:\Users\Smag\Documents\dev\community-server>
```

### Additional contract requirements

- When storing a root container identified by its base URL ending in `/`, the operation must succeed rather than fail with `BadRequestHttpError: URL needs a / after the base`. This requirement concerns root-container storage operations; it does not add a separate requirement about server startup or `-f` parsing.
