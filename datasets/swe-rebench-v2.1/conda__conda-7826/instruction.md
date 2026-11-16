Add expansion of environment variables in `channels` config key
As per https://github.com/conda/conda/issues/1156#issuecomment-299913430, can we get expansion of environment variables in the `channels` config key? This would be useful for me, as I can then add the following lines to my `.condarc` file:

```
channels:
  - https://${USERNAME}:${PASSWORD}@my.private.conda.channel
```

### Additional contract requirements

- When a channel value in the `channels` setting contains an environment-variable placeholder written as `${NAME}`, the placeholder is replaced by the value of the environment variable `NAME` when the channel list is read. For example, with `USERNAME=user22` and `PASSWORD=pass44` set, the entry `https://${USERNAME}:${PASSWORD}@my.private.conda.channel` yields `https://user22:pass44@my.private.conda.channel`.
