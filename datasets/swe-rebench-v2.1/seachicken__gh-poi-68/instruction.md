Delete the tracking branch as well.
### Description
I would like the tracking branch `(remotes/origin/****)` removed at the same time.

### Steps to reproduce
1. Ensure that the merged branch remains.
    ```sh
    $ git branch -a

      some-topic-branch
    * main
      remotes/origin/some-topic-branch
      remotes/origin/HEAD -> origin/main
      remotes/origin/main
    ```
1. Run gh-poi
    ```sh
    $ gh-poi

    ✔ Fetching pull requests...
    ✔ Deleting branches...

    Deleted branches
      Some-topic-branch
        └─ #1  https://github.com/Okako-WebWorks/TicketSystem/pull/***

    Not deleted branches
    * main
    ```

1. Ensure that the tracking branch remains in place.
    ```sh
    $ git branch -a

    * main
      remotes/origin/some-topic-branch
      remotes/origin/HEAD -> origin/main
      remotes/origin/main
    ```

1. Run prune
    ```
    $ git fetch --prune

     - [deleted]         (none)     -> origin/some-topic-branch
    ```

1. Now, all branches was cleaned!
    ```
    $ git branch -a

    * main
      remotes/origin/HEAD -> origin/main
      remotes/origin/main
    ```

Perhaps the prune executed here should be done by gh-poi.
(The above command may not be sufficient to avoid gh-poi deleting tracking branches other than the one you deleted.)

### Additional context
gh version 2.14.3 (2022-07-26)
gh poi  seachicken/gh-poi  v0.5.6

### Additional contract requirements

- Add a public function `GetRemote(connection Connection) (Remote, error)` in package `main` (file `poi.go`) that returns the primary remote repository (its `Name`, `Hostname` and `RepoName` fields), resolving the SSH hostname when necessary, or an error when the primary remote cannot be determined.
- Change the public function `GetBranches` in package `main` (file `poi.go`) to `GetBranches(remote Remote, connection Connection, dryRun bool) ([]Branch, error)`, taking the primary remote returned by `GetRemote`.
