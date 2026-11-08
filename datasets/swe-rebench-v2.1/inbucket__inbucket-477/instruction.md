[Rest Client] baseURL - unable to use a starting url
Currently only a hostname works with the "baseURL". If I put inbucket behind and api-server or proxy, and give it a path like:
```
https://my-api-server.example.com/inbucket
```

Then when I try and set this as the baseUrl, `https://my-api-server.example.com/api/v1` is used for rest requests instead of `https://my-api-server.example.com/inbucket/api/v1`
