New version not detected if the package is in the same lerna monorepo
Hi @rarkins, very nice job for renovate, I am using it in one of my projects https://github.com/CPatchane/create-cozy-app which is a monorepo and it works great 🎉

I just noticed something that seems to be a bug:
I have two packages in my monorepo `eslint-config-cozy-app` and `babel-preset-cozy-app` which are used as dependencies by my main package `cozy-scripts`. When I release a new version for all (using `lerna publish`), I expect to get new PRs from renovate to update `eslint-config-cozy-app` and `babel-preset-cozy-app` in my package `cozy-scripts` but it never happens. Even now, I just released new packages, I try renovate locally and it didn't see new  `eslint-config-cozy-app` and `babel-preset-cozy-app` packages.

I don't see any configurations about that, is it a wanted behaviour? Or maybe I am doing something wrong so I opened this issue to get answers.

Thanks!

### Additional contract requirements

A dependency must not be suppressed from normal version lookup merely because its name appears among the repository's discovered monorepo packages. Treat it as an internal dependency only when the containing package file belongs to the corresponding Lerna project or Yarn workspace; otherwise keep it eligible for version updates and update pull requests.
