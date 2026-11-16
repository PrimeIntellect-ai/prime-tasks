Error message should suggest `cargo vet fmt` on consistency errors?
After I resolved a git merge conflict in `imports.lock` by hand, I got the following error in CI where `cargo vet --locked` was run:

```
ERROR   × Your cargo-vet store (supply-chain) has consistency errors

Error:   × A file in the store is not correctly formatted:
(snip)
  help: run `cargo vet` without --locked to reformat files in the store
```

When I followed the help message and ran `cargo vet` without `--locked`, it didn't produce any change to the files in the store. (In case it ends up mattering, I did have a significant list of audits still suggested for safe-to-deploy.) I checked `--help` and decided the right command to run was `cargo vet fmt`, which did resolve this problem: `cargo vet --locked` no longer complains about the consistency errors, and it tells me which audits I am missing.

### Additional contract requirements

- For file-formatting errors, emit the exact help line "help: run `cargo vet fmt` to reformat files in the store".
