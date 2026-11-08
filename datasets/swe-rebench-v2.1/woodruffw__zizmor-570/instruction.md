[BUG]: couldn't parse expression
### Pre-submission checks

- [x] I am **not** filing a feature request. These should be filed via the feature request form instead.
- [x] I have looked through the [open issues](https://github.com/woodruffw/zizmor/issues?q=is%3Aissue+is%3Aopen+) for a duplicate report.

### Expected behavior

I expect zizmor not to give the following parse warnings on our admittedly-complex workflow files.

### Actual behavior

```console
❯ zizmor .
 INFO zizmor: skipping impostor-commit: can't run without a GitHub API token
 INFO zizmor: skipping ref-confusion: can't run without a GitHub API token
 INFO zizmor: skipping known-vulnerable-actions: can't run without a GitHub API token
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-windows.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-ubuntu.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/require-pr-label.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/new-bugs-announce-notifier.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/lint.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/tail-call.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/verify-ensurepip-wheels.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/jit.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-macos.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/add-issue-header.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/stale.yml
 WARN audit:audit{input=Workflow(file://./.github/workflows/reusable-context.yml)}: zizmor::audit::overprovisioned_secrets: couldn't parse expression: #        fromJSON(needs.build-context.outputs.run-tests)
      #        && 'truthy-branch'
      #        || 'falsy-branch'
      #
 WARN audit:audit{input=Workflow(file://./.github/workflows/reusable-context.yml)}: zizmor::audit::unredacted_secrets: couldn't parse expression: #        fromJSON(needs.build-context.outputs.run-tests)
      #        && 'truthy-branch'
      #        || 'falsy-branch'
      #
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-context.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-docs.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-tsan.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/mypy.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-windows-msi.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/documentation-links.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-wasi.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/project-updater.yml
 WARN audit:audit{input=Workflow(file://./.github/workflows/build.yml)}: zizmor::audit::overprovisioned_secrets: couldn't parse expression: #        fromJSON(needs.build-context.outputs.run-tests)
    #        && 'truthy-branch'
    #        || 'falsy-branch'
    #
 WARN audit:audit{input=Workflow(file://./.github/workflows/build.yml)}: zizmor::audit::overprovisioned_secrets: couldn't parse expression: '' } is a hack to nest jobs under the same sidebar category
      Windows MSI${{ ''
 WARN audit:audit{input=Workflow(file://./.github/workflows/build.yml)}: zizmor::audit::unredacted_secrets: couldn't parse expression: #        fromJSON(needs.build-context.outputs.run-tests)
    #        && 'truthy-branch'
    #        || 'falsy-branch'
    #
 WARN audit:audit{input=Workflow(file://./.github/workflows/build.yml)}: zizmor::audit::unredacted_secrets: couldn't parse expression: '' } is a hack to nest jobs under the same sidebar category
      Windows MSI${{ ''
 INFO audit: zizmor: 🌈 completed .github/workflows/build.yml
No findings to report. Good job! (1 ignored, 103 suppressed)
```


### Reproduction steps

```
git clone https://github.com/python/cpython # currently f963239ff1f986742d4c6bab2ab7b73f5a4047f6
cd cpython
zizmor .
```


### Logs

```plain text
❯ zizmor . --verbose
DEBUG zizmor::state: using cache directory: "/Users/hugo/.cache/zizmor"
DEBUG zizmor::config: loaded config: Config { rules: {"dangerous-triggers": AuditRuleConfig { ignore: [WorkflowRule { filename: "documentation-links.yml", line: None, column: None }] }} }
 INFO zizmor: skipping impostor-commit: can't run without a GitHub API token
 INFO zizmor: skipping ref-confusion: can't run without a GitHub API token
 INFO zizmor: skipping known-vulnerable-actions: can't run without a GitHub API token
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-windows.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-ubuntu.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/require-pr-label.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/new-bugs-announce-notifier.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/lint.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/tail-call.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/verify-ensurepip-wheels.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/jit.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-macos.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/add-issue-header.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/stale.yml
 WARN audit:audit{input=Workflow(file://./.github/workflows/reusable-context.yml)}: zizmor::audit::overprovisioned_secrets: couldn't parse expression: #        fromJSON(needs.build-context.outputs.run-tests)
      #        && 'truthy-branch'
      #        || 'falsy-branch'
      #
 WARN audit:audit{input=Workflow(file://./.github/workflows/reusable-context.yml)}: zizmor::audit::unredacted_secrets: couldn't parse expression: #        fromJSON(needs.build-context.outputs.run-tests)
      #        && 'truthy-branch'
      #        || 'falsy-branch'
      #
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-context.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-docs.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-tsan.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/mypy.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-windows-msi.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/documentation-links.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/reusable-wasi.yml
 INFO audit: zizmor: 🌈 completed .github/workflows/project-updater.yml
 WARN audit:audit{input=Workflow(file://./.github/workflows/build.yml)}: zizmor::audit::overprovisioned_secrets: couldn't parse expression: #        fromJSON(needs.build-context.outputs.run-tests)
    #        && 'truthy-branch'
    #        || 'falsy-branch'
    #
 WARN audit:audit{input=Workflow(file://./.github/workflows/build.yml)}: zizmor::audit::overprovisioned_secrets: couldn't parse expression: '' } is a hack to nest jobs under the same sidebar category
      Windows MSI${{ ''
 WARN audit:audit{input=Workflow(file://./.github/workflows/build.yml)}: zizmor::audit::unredacted_secrets: couldn't parse expression: #        fromJSON(needs.build-context.outputs.run-tests)
    #        && 'truthy-branch'
    #        || 'falsy-branch'
    #
 WARN audit:audit{input=Workflow(file://./.github/workflows/build.yml)}: zizmor::audit::unredacted_secrets: couldn't parse expression: '' } is a hack to nest jobs under the same sidebar category
      Windows MSI${{ ''
 INFO audit: zizmor: 🌈 completed .github/workflows/build.yml
No findings to report. Good job! (1 ignored, 103 suppressed)
```

### Additional context

_No response_

### Additional contract requirements

- The parse warnings shown above must not be emitted for expressions that
  appear inside comments, including commented-out expressions that are
  malformed (for example, missing a closing `}}`).
- The requirement applies to the audit output as a whole: running zizmor
  over a workflow or action file that contains such commented-out
  expressions must not produce these warnings.
- Filtering expressions inside comments must not suppress normal audit
  findings caused by valid expressions outside comments in the same
  workflow or action file.
