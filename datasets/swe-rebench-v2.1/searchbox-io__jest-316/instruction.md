NoSuchElementException - Concurrency issue on accessing the servers
FIrst of all thank you for this amazing library.
Now to the point, I'm doing a stress test where there is only one ES node. Everything works great, but randomly I'm receiving the error mentioned in the title and below. I'm using one ES node. I'm using Jest 1.0.1 with ES 1.7.2

```
JestClientFactory factory = new JestClientFactory();
factory.setHttpClientConfig(new HttpClientConfig
                .Builder(restEndpoint)
                .multiThreaded(true)
                .defaultCredentials(user, password)
                .requestCompressionEnabled(false)
                .build());

this.client = factory.getObject();
```

> java.util.NoSuchElementException: null
> 	at java.util.LinkedHashMap$LinkedHashIterator.nextNode(LinkedHashMap.java:713)
> 	at java.util.LinkedHashMap$LinkedKeyIterator.next(LinkedHashMap.jaThva:734)
> 	at com.google.common.collect.Iterators$4.next(Iterators.java:411)
> 	at io.searchbox.client.AbstractJestClient$ServerPool.getNextServer(AbstractJestClient.java:118)
> 	at io.searchbox.client.AbstractJestClient.getNextServer(AbstractJestClient.java:80)
> 	at io.searchbox.client.http.JestHttpClient.prepareRequest(JestHttpClient.java:80)
> 	at io.searchbox.client.http.JestHttpClient.execute(JestHttpClient.java:46)

The query is valid, as I've tested it via the marvel plugin.
