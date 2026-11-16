Supporting Basic HTTP auth in URL
Hi 👋

I have a staging server, which is protected with [basic HTTP authentication](https://en.wikipedia.org/wiki/Basic_access_authentication) to avoid accidental indexing by search engines. For manual testing, I simply enter login and password in the browser and for tools like [HTTPie](https://httpie.org/) or [Lighthouse](https://developers.google.com/web/tools/lighthouse/) I prepend my login and password to the URL like this:

```bash
http https://login:password@staging.example.com/
lighthouse --view https://login:password@staging.example.com/
```

All works – the response is 200.

However, `autocannon` seems to ignore my auth credentials written the same way:

```bash
autocannon https://login:password@staging.example.com/
```
```
Running 10s test @ https://login:password@staging.example.com/
10 connections

┌─────────┬───────┬───────┬────────┬────────┬─────────┬──────────┬───────────┐
│ Stat    │ 2.5%  │ 50%   │ 97.5%  │ 99%    │ Avg     │ Stdev    │ Max       │
├─────────┼───────┼───────┼────────┼────────┼─────────┼──────────┼───────────┤
│ Latency │ 77 ms │ 89 ms │ 117 ms │ 144 ms │ 93.8 ms │ 30.49 ms │ 394.45 ms │
└─────────┴───────┴───────┴────────┴────────┴─────────┴──────────┴───────────┘
┌───────────┬─────────┬─────────┬─────────┬─────────┬───────┬─────────┬─────────┐
│ Stat      │ 1%      │ 2.5%    │ 50%     │ 97.5%   │ Avg   │ Stdev   │ Min     │
├───────────┼─────────┼─────────┼─────────┼─────────┼───────┼─────────┼─────────┤
│ Req/Sec   │ 71      │ 71      │ 110     │ 117     │ 105.6 │ 12.54   │ 71      │
├───────────┼─────────┼─────────┼─────────┼─────────┼───────┼─────────┼─────────┤
│ Bytes/Sec │ 12.1 kB │ 12.1 kB │ 18.7 kB │ 19.9 kB │ 18 kB │ 2.13 kB │ 12.1 kB │
└───────────┴─────────┴─────────┴─────────┴─────────┴───────┴─────────┴─────────┘

Req/Bytes counts sampled once per second.

0 2xx responses, 1056 non 2xx responses
1k requests in 10.05s, 180 kB read
```

↑ `1056 non 2xx responses` suggests that HTTP auth was ignored and `401 Unauthorized` was returned in all cases. Could autocannon be improved so that it worked just like other tools with regards to basic auth?
