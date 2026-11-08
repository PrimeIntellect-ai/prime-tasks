Report and fix confusing quantifiers around assertions
**Description**
Assertions can be used to force certain quantifiers (or alternatives) to be entered.

E.g. in `a\b-?a`, the `\b` forces `-?` to be entered. The quantifier is useless in this case.
`a\b-?a` ==<sub>this issue</sub> `a\b-a` ==<sub>no-useless-assertions</sub> `a-a`.

We need to check all quantifiers with a minimum of 0 that are next to an assertion. If the assertion forces us to enter the quantifier, then the minimum should be 1 instead.

---

I think this should be part of `regexp/confusing-quantifier` but I'm not certain. What do you think @ota-meshi?

### Additional contract requirements

The rule is exported as the default export of `createRule("no-contradiction-with-assertion", { ... })` from `lib/rules/no-contradiction-with-assertion.ts` and is usable with ESLint's `RuleTester`.

When the rule reports a contradiction it uses one of the following message IDs:

- `alternative` - reported for an alternative that can never be entered because it contradicts an assertion. This report has no suggestions.
- `cannotEnterQuantifier` - reported for a quantifier that can never be entered because its element contradicts an assertion. Its suggestion removes the quantifier entirely (e.g. `/a\ba*-/` is fixed to `/a\b-/`).
- `alwaysEnterQuantifier` - reported for a quantifier with a minimum of 0 that is always entered because an assertion contradicts the element(s) after the quantifier. Its suggestion changes the quantifier so that its minimum is 1 while keeping its maximum; for a `?` quantifier this produces the `{1}` form (e.g. `/a\b-?a/` is fixed to `/a\b-{1}a/`).
