`()` file completion broken
Files containing `()` are currently truncated: `file()name -> file`

```go
10b4875b54ad7da4f2b6d6e10a7e73a2e219431a is the first bad commit
commit 10b4875b54ad7da4f2b6d6e10a7e73a2e219431a
Author: rsteube <rsteube@users.noreply.github.com>
Date:   Fri May 27 10:23:09 2022 +0200

    ToMultiParts: fix display

 action_test.go        |  1 -
 invokedAction.go      | 50 ++++++++++++++++++++++++++++++++++----------------
 invokedAction_test.go | 39 +++++++++++++++++++++++++++++++++++++++
 3 files changed, 73 insertions(+), 17 deletions(-)
 create mode 100644 invokedAction_test.go
bisect found first bad commit
```

caused-by: #534
