[BUG] Querying Data Streams Stats with AWS Auth without a name returns a signing error
### What is the bug?
When querying the Data Stream Stats API with AWS Authentication and without setting an index name the AWS Signature is invalid.

Error:
```
The request signature we calculated does not match the signature you provided.
Check your AWS Secret Access Key and signing method.
```

### How can one reproduce the bug?
Setup an AWS Signer and OpenSearch Client and make a request for `/_data_streams/_stats` without setting an index name.
```go
awsCfg, err := config.LoadDefaultConfig(context.Background())
if err != nil {
    return err
}

awsSigner, err := awsv2.NewSigner(awsCfg)
if err != nil {
    return err
}

url := "https://my-opensearch-cluster"
osCfg := opensearch.Config{
    Addresses: []string{url},
    Signer:    awsSigner,
}

client, err := opensearch.NewClient(osCfg)
if err != nil {
    return err
}

resp, err := client.Indices.GetDataStreamStats()
if err != nil {
    return err
}
```

### What is the expected behavior?
The list of data streams and their stats is returned. The OpenSearch API supports making this request with no name and should return all of the data streams instead.

### What is your host/environment?
Linux 6.2.6
Go 1.20.5

### Do you have any screenshots?
No

### Do you have any additional context?
[HIDDEN]

### Additional contract requirements

- The reproduction's `/_data_streams/_stats` path is inconsistent with the intended endpoint: with no name, the request path must be exactly `/_data_stream/_stats`. When a name is set, the path must be `/_data_stream/<name>/_stats`.
- When the client is configured with an AWS signer, a Data Stream Stats request with no name must be signed successfully: the outgoing request must carry an AWS `Authorization` header, and the signed path must be `/_data_stream/_stats` so the signature matches what the server computes.
