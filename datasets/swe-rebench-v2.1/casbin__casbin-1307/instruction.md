[Bug] Different types of role definition wrong g function
**Want to prioritize this issue? Try:**

[![issuehunt-to-marktext](https://github.com/BoostIO/issuehunt-materials/raw/master/v1/issuehunt-button-v1.svg)](https://issuehunt.io/r/casbin/casbin)

------

**Describe the bug**
G function will be override by wrong generated g function if we have at least *2* different types role definition.

https://github.com/casbin/casbin/blob/e46d08ee10207a3fd89972e40590f794612e27d1/enforcer.go#L584-L594

**To Reproduce**
https://go.dev/play/p/blXW5-bZ1ZA

**Screenshots**
<img width="970" alt="image" src="https://github.com/casbin/casbin/assets/17849741/197c5c9b-cc7c-40b3-a183-7d907414c766">

<img width="834" alt="image" src="https://github.com/casbin/casbin/assets/17849741/3d5e2b4a-9df2-4d4a-b46e-5a02bdc2e92e">

### Additional contract requirements

- Provide the regression fixtures at `examples/rbac_with_different_types_of_roles_model.conf` and `examples/rbac_with_different_types_of_roles_policy.csv`.
- The fixtures must yield grouping-policy rows for `g` with exactly 5 fields. After registering `util.TimeMatchFunc` for each row using `AddNamedDomainLinkConditionFunc("g", gp[0], gp[1], gp[2], util.TimeMatchFunc)`, enforcement must return: `true` for (`alice`, `data1`, `read`) and (`alice`, `data1`, `write`); `false` for (`alice`, `data2`, `read`), (`alice`, `data2`, `write`), (`bob`, `data1`, `read`), (`bob`, `data1`, `write`), (`bob`, `data2`, `write`), and all four combinations of `carol` with `data1` or `data2` and `read` or `write`; and `true` for (`bob`, `data2`, `read`).
