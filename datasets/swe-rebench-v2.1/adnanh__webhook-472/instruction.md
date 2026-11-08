Switching from 2.6.11 to 2.7.0 causes the same payloads to not match
Thanks for webhook!

Here are my rules: https://gist.github.com/gamerson/3cc9162082b9fe916b2d04b570e251f6

When I switched from 2.6.11 to 2.70, the same payload that was working before will now no longer work with the following error message:

```
[webhook] 2020/10/21 17:19:01 [aac923] incoming HTTP POST request from 172.17.0.1:42746
[webhook] 2020/10/21 17:19:01 [aac923] lugbot got matched
[webhook] 2020/10/21 17:19:01 [aac923] parameter node not found: ref
[webhook] 2020/10/21 17:19:01 [aac923] lugbot got matched, but didn't get triggered because the trigger rules were not satisfied
[webhook] 2020/10/21 17:19:01 [aac923] 200 | 30 B | 446.6µs | 629d73f917f7.ngrok.io | POST /hooks/lugbot
```

Here is a copy of the payload that would not match: https://gist.github.com/gamerson/f8e05eb879e7c30a537190a10b0011fd

### Additional contract requirements

- When an OR rule's sole match references a missing header parameter named `a`, evaluate the rule as `false` without returning an error.
