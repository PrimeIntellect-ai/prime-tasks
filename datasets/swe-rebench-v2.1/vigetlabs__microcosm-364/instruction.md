Presenter context between setup() and intercept() mismatch
**What kind of issue is this?** (check at least one)

- [x] Report a bug
- [ ] Feature Request
- [ ] Question
- [ ] Discussion
- [ ] Documentation
- [ ] Other, please describe:

**What version of Microcosm is this for**

12.9.0-beta

**Steps to Reproduce/Example** (if applicable)

Failing spec added [here](https://github.com/vigetlabs/microcosm/commit/604acafa31cedcfb87126753a6f1dbd0cfe0e052)

<!-- What is the expected behaviour? -->

Presenter `this` context should be shared between `setup()` and `intercept()`.

<!-- What is happening instead? -->

It looks like logging `this` in `setup()` returns an instance of the Presenter like I expected, but logging `this` in `intercept()` returns an instance of `PresenterMediator` so any attributes defined on `this` in `setup()` are lost in `intercept()`.
