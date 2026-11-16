Decouple ServiceKey namespace from KeyStoreAPI namespace
We are storing the ServiceKey in the same namespace as the one we use for the `KeyStoreAPI`. What this means is that a caller may override the ServiceKey that was stored, if they pass in `id == "ssi-service-key"` in the [Store Key Request](https://developer.tbd.website/docs/apis/ssi-service#tag/KeyStoreAPI/paths/~1v1~1keys/put)
