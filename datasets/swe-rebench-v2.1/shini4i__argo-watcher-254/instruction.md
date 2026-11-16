updater: support argo-cd applications with multiple sources
Currently argo-watcher updater supports direct commit integration with argo-cd applications with single source.

Since argo-cd version 2.6+ has the ability to specify multiple sources for a single Application.

### Additional contract requirements

- For an Application with multiple sources, direct Git write-back must place the image-tag override in the repository, branch, and path configured for write-back. The write-back target is read from the Application annotations `argo-watcher/write-back-repo`, `argo-watcher/write-back-branch`, and `argo-watcher/write-back-path`.
- For an Application with a single source, direct Git write-back must keep using the source's repository, target revision, and path.
