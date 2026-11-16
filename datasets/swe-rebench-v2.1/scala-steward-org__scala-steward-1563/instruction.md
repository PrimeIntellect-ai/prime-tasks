Compare url & release notes/changelog are restricted to {github,gitlab}.com
Current logic of generating compare url and release notes/changelog are restricted to either github.com or gitlab.com
```
if (repoUrl.startsWith("https://github.com/") || repoUrl.startsWith("https://gitlab.com/"))
```

Is it possible to configure/extend this, so that git enterprise urls (such as git.enterprise.company.com) can also be included in this?

### Additional contract requirements

- Add a public function `possibleCompareUrls(vcsType: SupportedVCS, vcsUri: Uri, repoUrl: Uri, update: Update): List[VersionDiff]` in the package object `vcs` (`org.scalasteward.core.vcs`), where `vcsType` is the configured VCS type and `vcsUri` is the configured VCS API base URI.
- Add a public function `possibleReleaseRelatedUrls(vcsType: SupportedVCS, vcsUri: Uri, repoUrl: Uri, update: Update): List[ReleaseRelatedUrl]` in the package object `vcs`.
- Add a public method `VCSExtraAlg.create[F[_]](implicit existenceClient: HttpExistenceClient[F], config: Config, F: Monad[F]): VCSExtraAlg[F]` in the object `VCSExtraAlg`.
