Estuary publisher errors bubble up even if IPFS publishing succeeds
Re: https://filecoinproject.slack.com/archives/C02RLM3JHUY/p1677007150334469

What's meant to happen is that errors from publishing to Estuary only appear if our own IPFS push also fails. What seems to happen right now is that any Estuary error appears immediately.

Probably due to https://github.com/filecoin-project/bacalhau/blob/41298e8ad1f8d0fedc6955d8211f9a4fc55b702b/pkg/publisher/combo/fanout.go#L163-L165

This should probably sit on the error and only return it if the other publishers in the fan out ALL fail.
