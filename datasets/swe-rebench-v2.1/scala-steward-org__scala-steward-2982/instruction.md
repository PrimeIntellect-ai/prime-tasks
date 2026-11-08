Creating `.git-blame-ignore-revs` can error the Scala Steward process if that file is covered by `gitignore`
The Guardian's [Scala Steward GitHub Action](https://github.com/guardian/scala-steward-public-repos/actions/workflows/public-repos-scala-steward.yml) (covering all the public repos in our GitHub org) job [started erroring](https://github.com/guardian/support-service-lambdas/pull/1834), and the culprit turned out to be the `git add .git-blame-ignore-revs` added with https://github.com/scala-steward-org/scala-steward/pull/2652 :

```
2023-01-19 10:02:07,438 ERROR Steward guardian/support-service-lambdas failed
  java.io.IOException: 'GIT_ASKPASS=/home/runner/scala-steward/askpass.sh "SBT_OPTS=-Xmx2048m -Xss8m -XX:MaxMetaspaceSize=512m" git -c core.hooksPath=/dev/null add /home/runner/scala-steward/workspace/repos/guardian/support-service-lambdas/.git-blame-ignore-revs' exited with code 1
  The following paths are ignored by one of your .gitignore files:
  .git-blame-ignore-revs
  hint: Use -f if you really want to add them.
  hint: Turn this message off by running
  hint: "git config advice.addIgnoredFile false"
```

It turns out we had [quite broad](https://github.com/guardian/support-service-lambdas/blob/4952dab4c35793b620e82b6f338244628e071962/.gitignore#L1) gitignore configuration in the repo (ignoring all files starting with `.` by default). The file `.git-blame-ignore-revs` starts with a `.`, and `git add` doesn't like adding files that are gitignored.

The gitignore configuration in the troublesome repo is quite easily fixed once the problem's identified, but it took a bit of digging to understand what the issue was, and so I was wondering if there was a possible improvement to Scala Stewards behaviour here? Some possible options:

* **Force `git add`** : [HIDDEN]
* **Informative warning** : Somehow test if `.git-blame-ignore-revs` can be added, and if not, just provide a friendly warning, rather than having the entire job (which, for a GitHub action, can cover a very large number of repos) being marked as a 'Failure'. ![image](https://user-images.githubusercontent.com/52038/214324817-9f108c2b-408b-4de8-bf7d-fe6effc4aae7.png)




I'm not sure which approach would be considered best, but I could have a go at a PR for **Force `git add`**, if that would be helpful.

### Additional contract requirements

- When `.git-blame-ignore-revs` is covered by a gitignore rule, the update must not fail the Scala Steward process because of it. Scala Steward either adds and commits the file anyway, or skips adding it and logs a warning that the file was not added because it is git ignored.
- When `.git-blame-ignore-revs` is not covered by a gitignore rule, the update behaves as before: the entry is written to the file, the file is added, and it is committed with the message `Add '<update title>' to .git-blame-ignore-revs`.
