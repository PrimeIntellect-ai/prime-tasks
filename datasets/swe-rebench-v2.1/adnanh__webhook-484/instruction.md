webhook IDs can't be paths?

I'm confused why I can't get webhook id's with paths in them to work?

```
[webhook] 2020/05/19 01:46:46 found 3 hook(s) in file
[webhook] 2020/05/19 01:46:46   loaded: test
[webhook] 2020/05/19 01:46:46   loaded: test_2
[webhook] 2020/05/19 01:46:46   loaded: test_2/canwepath
```

You can see all three hooks are found; however, the only ones that I can actually `POST` to are `test` and `test_2`. If I try to send a request to `test_2/canwepath` I get  `404 Not Found`

Would appreciate any help here; not sure what I'm missing. Kind of a bummer because the API I'm trying to receive requests from uses paths in their IDs
