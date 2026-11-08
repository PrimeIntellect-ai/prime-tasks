Formik removes class prototype on top level state
## 🐛 Bug report

### Current Behavior

If you use a class for the initialValues prop, when you update anything on that top level, Formik converts it to a basic Javascript object. It does not do this for nested objects; just the top level.

### Expected behavior

Formik should keep the class methods and prototype when the form updates at top level.

### Reproducible example

https://codesandbox.io/s/8nkm0nrz59
Note that changing any box will cause the top level object to no longer be an instanceof FormikState, but changing the third box does not cause the nested object to lose its instanceof FormikNestedState

### Suggested solution(s)

Haven't looked into the code yet, but I'm assuming there's something like an `Object.assign({}, updatedState)` or similar. [HIDDEN]
Edit: Looks like this is the issue: https://github.com/jaredpalmer/formik/blob/3242489e0cd7b68bad16494b749e43129a2cadbd/src/utils.ts#L57

### Additional context

We're trying to use a method on the initialState class object to determine if we should disable a button or not. Having the class get blown away makes that not possible from within that class. We have that logic in the component itself, but would like to abstract parts of it away into this class. The fact that this behavior is inconsistent at top level vs nested means this is probably an edge case.

### Your environment

| Software         | Version(s) |
| ---------------- | ---------- |
| Formik           | 1.5.1 (latest atm)
| React            | 16.8.3
| TypeScript       | 3.3.3333
| Browser          | Chrome
| npm/Yarn         | yarn 1.13.0
| Operating System | macOs
