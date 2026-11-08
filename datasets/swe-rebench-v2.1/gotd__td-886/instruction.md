tg.Config: load: unmarshal: json: cannot unmarshal object into Go struct field
<!-- Please answer these questions before submitting your issue. Thanks! -->

### What version of gotd are you using?
v0.69.1-0.20220919134912-f8b8bd891200

### Can this issue be reproduced with the latest version?

Yes

### What did you do?

run the client repeatedly

### What did you expect to see?

It runs successfully.

### What did you see instead?

```
2022-09-21T09:24:33.320+0800	INFO	client.conn.mtproto.rpc	rpc/engine.go:42	Initialized	{"v": "v0.69.1-0.20220919134912-f8b8bd891200", "conn_id": 0, "dc_id": 2, "retry_interval": "1s", "max_retries": 10}
2022-09-21T09:24:33.320+0800	INFO	client	telegram/connect.go:114	Starting	{"v": "v0.69.1-0.20220919134912-f8b8bd891200"}
2022-09-21T09:24:33.321+0800	INFO	client	telegram/connect.go:131	Closed	{"v": "v0.69.1-0.20220919134912-f8b8bd891200"}
load: unmarshal: json: cannot unmarshal object into Go struct field Config.Data.Config.ReactionsDefault of type tg.ReactionClass
```

After https://github.com/gotd/td/pull/880, `tg.Config` has added a `ReactionDefault` interface type that cannot be parsed to go struct when json unmarshal.

### What Go version and environment are you using?
v1.18.5
