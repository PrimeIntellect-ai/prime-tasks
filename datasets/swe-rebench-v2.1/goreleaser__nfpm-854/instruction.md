Ability to specify %config(missingok)
### Is your feature request related to a problem? Please describe.

It's great to have a `%config(noreplace)` when building RPMs. Now we stumbled over the need to specify `%config(missingok)`.

This is especially made for cases where the package manager is happy with the file being there or missing. Given files you only need within postInstall scripts, symlinks that vanish or others.

### Describe the solution you'd like

Would be great to simply be able to pass `type: config|missingok` to a "content".

### Describe alternatives you've considered

Writing spec files by hand and not using nfpm. Which is somewhat not a real alternative :innocent:

### Search

- [X] I did search for other open and closed issues before opening this.

### Code of Conduct

- [X] I agree to follow this project's Code of Conduct

### Additional context

https://rpm-software-management.github.io/rpm/manual/spec.html#missingok-since-rpm--414-in-standalone-form
