Subsequent `DynamicStore.Put` calls do not set credential store once failure
In the following code block:
https://github.com/oras-project/oras-go/blob/8d139f0be9190ee4e48fe00cda08e0185ccd2494/registry/remote/credentials/store.go#L136-L152

If `ds.setCredsStoreOnce` fails on the first call to `Put`, the subsequent calls to `Put` will never attempt to set the credential store again but return success.
