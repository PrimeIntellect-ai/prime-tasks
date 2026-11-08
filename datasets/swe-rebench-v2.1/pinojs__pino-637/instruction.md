Missing message when using with pretty print
The latest version of pino (5.12.1), this pull request to be exact https://github.com/pinojs/pino/pull/635, causes message to be undefined when passing to pretty-print if logging using only Object like the following:

```
const logger = pino({
  prettyPrint: true,
})
logger.info({ msg: 'test!' })
```

Expected Output:
```
[1554452604021] INFO  (3605 on re7eal-VirtualBox): test!
```

Output:
```
[1554452604021] INFO  (3605 on re7eal-VirtualBox):
```
