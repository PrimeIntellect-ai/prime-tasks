bug: relative locators fails for quickstart package
### What's your CLI version?

0.83.7

### Description & steps to reproduce

There is another bug related to relative imports this time happens with the  quickstart packagein theawesome repository and it seems it happens when a package uses relative reference to a sibling package, data-packgein this case.
[If you check this change](https://github.com/kurtosis-tech/awesome-kurtosis/pull/187/files#diff-abf5ef9d44740e5825e0f95de966f699d74df8f7948ef4183ff1a821a57947c7R7) you will see  the data-package/main.star file is uploading a file inside the same repo using a relative path, and then [if you check here](https://github.com/kurtosis-tech/awesome-kurtosis/blob/main/quickstart/main.star#L1)  you will see that quickstart package is importing this module from its sibling, so when you run `kurtosis run [github.com/kurtosis-tech/awesome-kurtosis/quickstart](http://github.com/kurtosis-tech/awesome-kurtosis/quickstart) it fails (I reverted the change so it won’t fails now) you can also [see the error in the mono-repo CI test](https://app.circleci.com/pipelines/github/kurtosis-tech/kurtosis/7072/workflows/ba012562-5cb2-480e-b49b-806592107a01/jobs/95120) because it’s using it.

It seems the relative path works when quickstart is executed in awesome CI (because I think it’s doing kurtosis run .) but the relative breaks when it’s executed from the mono repo, because, It does `kurtosis run [github.com/kurtosis-tech/awesome-kurtosis/quickstart](http://github.com/kurtosis-tech/awesome-kurtosis/quickstart)

We created an example to reproduce the issue:

`kurtosis run github.com/h4ck3rk3y/package-panic/primary`   will break meanwhile

`kurtosis run [github.com/h4ck3rk3y/package-panic/data`  will works.


### Desired behavior

Quickstar package can use relative locators

### What is the severity of this bug?

Painful; this is causing significant friction in my workflow.

### Additional contract requirements

- A package must be able to reference a sibling package's files within the same repository using a relative locator.
- When resolving a relative locator, a locator that starts with `/` is resolved relative to the package root (the directory containing the package's `kurtosis.yml`). For example, resolving `/static_files/genesis.json` from a module located at `github.com/kurtosis-tech/avalanche-package/src/builder.star` yields `github.com/kurtosis-tech/avalanche-package/static_files/genesis.json`.
- A relative locator that does not start with `/` (for example `../static_files/config.json.tmpl`) is resolved relative to the directory of the file that contains the locator. For example, resolving `../static_files/config.json.tmpl` from a module located at `github.com/kurtosis-tech/avalanche-package/src/builder.star` yields `github.com/kurtosis-tech/avalanche-package/static_files/config.json.tmpl`.
