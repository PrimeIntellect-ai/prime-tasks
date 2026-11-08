Reconnect DB after closing.
## Description

If this is a feature request, explain why it should be added. Specific use-cases are best.

For bug reports, please provide as much *relevant* info as possible.

When `Connection`  closed, it unable to open again.

### Steps to Reproduce the Problem

  Please describe in painful detail what you did (so others can play along with you) to get to this point. This includes things like the exact command(s) you used, or the `curl` command you used, that sort of thing.

```go
	users := []User{}
	for i := 0; i < 2; i++ {
		conn, err := pop.Connect("development")
		if err != nil {
			fmt.Println(err)
		}
		err = conn.All(&users)
		if err != nil {
			fmt.Println(err)
			os.Exit(1)
		}
		for _, u := range users {
			fmt.Println(u)
		}
		err = conn.Close()
		[HIDDEN]
		if err != nil {
			fmt.Println(err)
		}
	}
```
### Expected Behavior

connection will recconnect after closing

### Actual Behavior

```
unable to fetch records: sql: database is closed
```

### Info

[HIDDEN]

### Additional contract requirements

- A closed connection can be opened again and used successfully for a database operation.
