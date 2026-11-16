Add flag for selecting all of the default options
@phillipskevin commented on [Thu Jan 26 2017](https://github.com/donejs/cli/issues/71)

It would be nice if you could do something like

```
donejs add app my-app --yes
```

and have all of the default options selected without having to hit enter for every question.

---

@matthewp commented on [Wed Feb 15 2017](https://github.com/donejs/cli/issues/71#issuecomment-280026990)

Shouldn't this be a generator-donejs issue? You couldn't support this universally, I don't think, like `donejs add firebase --yes` wouldn't work. Hopefully the cli flags are passed to the generator some how, and they can interpret them as they wish.

---

@phillipskevin commented on [Wed Feb 15 2017](https://github.com/donejs/cli/issues/71#issuecomment-280047657)

Actually, this is a donejs/donejs issue first, and then a generator-donejs issue. We need to add a command line flag here: [HIDDEN] or commander will exit with `error: unknown option '--yes'`.

### Additional contract requirements

- `donejs add app <folder> --yes` must be accepted by the CLI; it must not fail with an unknown option error.
- When `--yes` is given for a new app, the `donejs init` command that the CLI runs for that app must receive `--yes`, so the generator can use its defaults without prompting.
- When `--yes` is not given, the `donejs init` command must not receive `--yes`.
