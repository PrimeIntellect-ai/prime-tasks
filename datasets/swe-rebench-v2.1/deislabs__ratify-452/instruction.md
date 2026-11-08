Docker config auth provider should work with identity tokens
## Problem

The ORAS store currently supports the [Docker config file](https://github.com/deislabs/ratify/blob/main/docs/reference/oras-auth-provider.md#1-docker-config) as an authentication provider, which is useful for development and standalone usage of Ratify (ex: in a CI pipeline)

The Docker config file format supports [multiple types](https://github.com/docker/cli/blob/master/cli/config/types/authconfig.go) of credentials, including `password` (already supported [here](https://github.com/deislabs/ratify/blob/9c682011a0c5da32d986b748b1e66541344ba843/pkg/referrerstore/oras/authprovider/authprovider.go#L126-L131)) and `identitytoken`, which does not work

This leads to a poor experience when used with tools that set `identitytoken`, ex: `az acr login`. Currently I have to introduce hacky conversion commands so that Ratify picks up the `password` property for use with ORAS:

```shell
# login to my registry
az acr login -n $MYREGISTRY

# hack to convert identitytoken -> password
cat <<< $(jq --arg registry $REGISTRY '.auths[$registry] |= {"username":"00000000-0000-0000-0000-000000000000", "password": .identitytoken }' <~/.docker/config.json) > ~/.docker/config.json

# verify some assets
ratify verify $MYREGISTRY.azurecr.io/myimage:sometag
```

## Proposed solution

It would be great if Ratify supported `identitytoken` so that I could create a pipeline with the following flow, without having to jump through the above hoops to get authenticated

```shell
az acr login -n $MYREGISTRY
ratify verify $MYREGISTRY.azurecr.io/myimage:sometag
```

Working proof of concept here: https://github.com/cse-labs/ratify/commit/47967b7b76f675197726258562802c0ec5560a53
