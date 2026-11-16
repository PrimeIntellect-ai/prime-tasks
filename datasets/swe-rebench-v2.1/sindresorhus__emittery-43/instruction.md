Support Symbol as `eventName`
<!-- Issuehunt Badges -->
[<img alt="Issuehunt badges" src="https://img.shields.io/badge/IssueHunt-%2460%20Funded-%2300A156.svg" />](https://issuehunt.io/r/sindresorhus/emittery/issues/16)
<!-- /Issuehunt Badges -->


See https://github.com/sindresorhus/emittery/issues/12#issuecomment-348813948 for use-case.

I think #13 should be implemented first though, so we can make sure it's not hard to define in a TS type definition.

---

> *Note: This issue has a bounty, so it's expected that you are an experienced programmer and that you give it your best effort if you intend to tackle this. Don't forget, if applicable, to add tests, docs (double-check for typos), and update TypeScript definitions. And don't be sloppy. Review your own diff multiple times and try to find ways to improve and simplify your code. Instead of asking too many questions, present solutions. The point of an issue bounty is to reduce my workload, not give me more. Include a 🦄 in your PR description to indicate that you've read this. Thanks for helping out 🙌* - @sindresorhus


<!-- Issuehunt content -->

---

<details>
<summary>
<b>IssueHunt Summary</b>
</summary>


### Backers (Total: $60.00)

- [<img src='https://avatars3.githubusercontent.com/u/44827199?v=4' alt='issuehunt' width=24 height=24> issuehunt](https://issuehunt.io/u/issuehunt) ($60.00)
### Submitted pull Requests
- [#43 Allow symbol event names](https://issuehunt.io/r/sindresorhus/emittery/pull/43)
---

#### [Become a backer now!](https://issuehunt.io/r/sindresorhus/emittery/issues/16)
#### [Or submit a pull request to get the deposits!](https://issuehunt.io/r/sindresorhus/emittery/issues/16)
### Tips

- Checkout the [Issuehunt explorer](https://issuehunt.io/r/sindresorhus/emittery/) to discover more funded issues.
- Need some help from other developers? [Add your repositories](https://issuehunt.io/r/new) on IssueHunt to raise funds.
---
IssueHunt has been backed by the following sponsors. [Become a sponsor](https://issuehunt.io/membership/members)
</details>
<!-- /Issuehunt content-->

### Additional contract requirements

The public TypeScript declarations must accept `symbol` event names wherever the emitter API accepts event names. This includes the untyped emitter API and `Emittery.Typed`: symbol keys for events with data and symbol names for empty events must be usable with their corresponding typed methods. At runtime, symbols must also be accepted wherever string event names are accepted, including event iterators, per-event listener clearing, listener counts, and catch-all observers. Catch-all observers must receive the original symbol identity together with the event data.
