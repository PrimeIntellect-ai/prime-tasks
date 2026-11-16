Inconsistent checking of identities
There appear to be two separate functions for checking identities (e.g. author, committer):
* [`dulwich.repo.check_user_identity`](https://github.com/jelmer/dulwich/blob/1668d09bf7547ce1b81b114793e5454dc9cf0adf/dulwich/repo.py#L216-L229)
* [`dulwich.objects.check_identity`](https://github.com/jelmer/dulwich/blob/1668d09bf7547ce1b81b114793e5454dc9cf0adf/dulwich/objects.py#L196-L215)

The first one is called in `Repo.do_commit`, the second one in `Commit.check`. They behave differently (in an incomparable manner) from each other and from git version 2.37.

| Example | check_identity | check_user_identity | git commit |
|---|---|---|---|
| `a <>` | accept | accept | accept |
| `a <> b` | reject | accept | accept |
| `a<>` | accept | reject | accept |
| `a<>b` | reject | reject | accept |
| `\0 <>` | accept | accept | reject |
| `\n <> b` | reject | accept | reject |
| `\n<>` | accept | reject | reject |
| `a` | reject | reject | reject |

What is the desired behaviour in this project?

### Additional contract requirements

- `dulwich.objects.check_identity` must reject `b'<dborowitz@google.com>'` by raising `ObjectFormatException`.
- `dulwich.objects.check_identity` must reject an identity that contains a NUL byte or a newline byte by raising `ObjectFormatException`.
- `dulwich.repo.check_user_identity` must reject an identity that contains a NUL byte or a newline byte by raising `InvalidUserIdentity`.
