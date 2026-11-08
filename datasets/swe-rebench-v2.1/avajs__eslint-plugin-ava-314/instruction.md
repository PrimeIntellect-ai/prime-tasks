The `assertion-arguments` rule should validate message argument type
<!-- Issuehunt Badges -->
[<img alt="Issuehunt badges" src="https://img.shields.io/badge/IssueHunt-%2460%20Funded-%2300A156.svg" />](https://issuehunt.io/r/avajs/eslint-plugin-ava/issues/167)
<!-- /Issuehunt Badges -->


This currently passes `t.deepEqual({}, {}, {});`, which can make for some hard to debug issues. @gajus [reported](https://gitter.im/avajs/ava?at=5880e744e836bf70106558a4) such issue on Gitter.

We should ensure that if `message` is specified, it's a string. We could implement inline literal validation first, as that's pretty easy.

We should also detect the type if it's a variable defined in the same scope:

```js
const message = 'foo';

...

t.deepEqual({}, {}, message);
```

@jfmengels Many rules could use some kind of naive type inference. Maybe [`eslint-ast-utils`](https://github.com/jfmengels/eslint-ast-utils) could add something like that?

---

> *Note: This issue has a bounty, so it's expected that you are an experienced programmer and that you give it your best effort if you intend to tackle this. Don't forget, if applicable, to add tests, docs (double-check for typos). And don't be sloppy. Review your own diff multiple times and try to find ways to improve and simplify your code. Instead of asking too many questions, present solutions. The point of an issue bounty is to reduce my workload, not give me more. Include a 🦄 in your PR description to indicate that you've read this. Thanks for helping out 🙌* - @sindresorhus


<!-- Issuehunt content -->

---

<details>
<summary>
<b>IssueHunt Summary</b>
</summary>


### Backers (Total: $60.00)

- [<img src='https://avatars3.githubusercontent.com/u/44827199?v=4' alt='issuehunt' width=24 height=24> issuehunt](https://issuehunt.io/u/issuehunt) ($60.00)

### Submitted pull Requests
- [#314 Add check for the assertion message to be a string](https://issuehunt.io/r/avajs/eslint-plugin-ava/pull/314)
---

#### [Become a backer now!](https://issuehunt.io/r/avajs/eslint-plugin-ava/issues/167)
#### [Or submit a pull request to get the deposits!](https://issuehunt.io/r/avajs/eslint-plugin-ava/issues/167)
### Tips

- Checkout the [Issuehunt explorer](https://issuehunt.io/r/avajs/eslint-plugin-ava/) to discover more funded issues.
- Need some help from other developers? [Add your repositories](https://issuehunt.io/r/new) on IssueHunt to raise funds.
</details>
<!-- /Issuehunt content-->

### Additional contract requirements

When an assertion message argument is present but is not a string, the rule must report a diagnostic whose message is exactly:

```
Assertion message should be a string.
```
