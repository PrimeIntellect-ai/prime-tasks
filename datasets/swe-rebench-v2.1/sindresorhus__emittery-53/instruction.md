Built-in debug info
<!-- Issuehunt Badges -->
[<img alt="Issuehunt badges" src="https://img.shields.io/badge/IssueHunt-%2440%20Funded-%2300A156.svg" />](https://issuehunt.io/r/sindresorhus/emittery/issues/2)
<!-- /Issuehunt Badges -->


Running `DEBUG=emittery node x.js` or `DEBUG=* node x.js` should output debug information/trace of events.

Events can be hard to debug, so this is important.

I'm looking for feedback on what the trace output should look like.

---

*I don't want to depend on the `debug` module, but we could easily detect the environment variable manually.*


<!-- Issuehunt content -->

---

<details>
<summary>
<b>IssueHunt Summary</b>
</summary>


### Backers (Total: $40.00)

- [<img src='https://avatars3.githubusercontent.com/u/44827199?v=4' alt='issuehunt' width=24 height=24> issuehunt](https://issuehunt.io/u/issuehunt) ($40.00)

### Submitted pull Requests
- [#53 Implements debug feature as described in #2](https://issuehunt.io/r/sindresorhus/emittery/pull/53)
---

#### [Become a backer now!](https://issuehunt.io/r/sindresorhus/emittery/issues/2)
#### [Or submit a pull request to get the deposits!](https://issuehunt.io/r/sindresorhus/emittery/issues/2)
### Tips

- Checkout the [Issuehunt explorer](https://issuehunt.io/r/sindresorhus/emittery/) to discover more funded issues.
- Need some help from other developers? [Add your repositories](https://issuehunt.io/r/new) on IssueHunt to raise funds.
---
IssueHunt has been backed by the following sponsors. [Become a sponsor](https://issuehunt.io/membership/members)
</details>
<!-- /Issuehunt content-->

### Additional contract requirements

- When the `DEBUG` environment variable is set to `emittery` or `*`, emitting a named event on an Emittery instance writes a trace line to the console, and that line includes the event name.
- When `DEBUG` is not set, emitting events writes no trace output.
- Tracing does not change delivery: listeners still receive the emitted data unchanged, including for symbol event names and object data.
- Tracing does not add a runtime dependency on the `debug` package.
