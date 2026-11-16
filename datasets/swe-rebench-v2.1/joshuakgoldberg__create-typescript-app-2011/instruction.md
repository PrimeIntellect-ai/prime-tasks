🐛 Bug: blockPackageJson unable to update lockfile in transition mode CI
### Bug Report Checklist

- [x] I have tried restarting my IDE and the issue persists.
- [x] I have pulled the latest `main` branch of the repository.
- [x] I have [searched for related issues](https://github.com/JoshuaKGoldberg/create-typescript-app/issues?q=is%3Aissue) and found none that matched my issue.

### Expected

Running `pnpx create-typescript-app` as transition mode in CI should update the `pnpm-lock.yaml` file.

### Actual

It's not currently, because [`--no-frozen-lockfile`](https://pnpm.io/cli/install#--frozen-lockfile) is not set.

### Additional Info

🎁

### Additional contract requirements

- The generated install command must include `--no-frozen-lockfile` in default and transition modes. When offline mode is enabled, the command must be `pnpm install --offline --no-frozen-lockfile`.
