🐛 Bug: Transition action failing in PRs from fork
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

The `.github/workflows/cta.yml` action added by `--add-cta-transitions` should not run at all, let alone fail, if in a PR that's not a `create-typescript-app` devDependency bump.

### Actual

From https://github.com/JoshuaKGoldberg/formatly/pull/115 -> https://github.com/JoshuaKGoldberg/formatly/actions/runs/14529409764/job/40766624056?pr=115:

```plaintext
Run actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683
Error: Input required and not supplied: token
```

### Additional Info

🎁
