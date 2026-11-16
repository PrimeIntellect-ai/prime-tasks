`parse_diff_output()` raises AssertionError in v3.12
Hello, and thanks for creating this GH Action! I have a workflow that fails on v3.12 but succeeds on v3.11...

<details>
<summary>Stack trace from failing workflow run when using v3.12...</summary>

```bash
Notice: Generating comment for PR
Error: Critical error. This error possibly occurred because the permissions of the workflow are set incorrectly. You can see the correct setting of permissions here: https://github.com/py-cov-action/python-coverage-comment-action#basic-usage
Otherwise please look for open issues or open one in https://github.com/py-cov-action/python-coverage-comment-action/
Traceback (most recent call last):
  File "/usr/local/lib/python3.11/site-packages/coverage_comment/main.py", line 40, in main
    exit_code = action(
                ^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/coverage_comment/main.py", line 92, in action
    return process_pr(
           ^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/coverage_comment/main.py", line 121, in process_pr
    added_lines = coverage_module.get_added_lines(git=git, base_ref=base_ref)
                  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/coverage_comment/coverage.py", line 279, in get_added_lines
    return parse_diff_output(diff)
           ^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.11/site-packages/coverage_comment/coverage.py", line 291, in parse_diff_output
    assert current_file
AssertionError
```

</details>

It falls over on the line below, where it looks like `current_file` never gets updated: https://github.com/py-cov-action/python-coverage-comment-action/blob/08f2d84b93f75ccaf3431cefae8690571965981c/coverage_comment/coverage.py#L291

Here's an example of an input `diff` for this function that fails on v3.12, but passes when I pin the action to v3.11:

<details>
<summary>Sample diff for `parse_diff_output()`...</summary>


> **Note**
> This diff was created by inserting the following step into the workflow directly before the `python-coverage-comment-action` step:
>
> ```yaml
>      - name: Debug CI on host
>        run: |
>          sudo apt-get install -y tree \
>            && tree -a . \
>            && git fetch origin dev --depth=1000 \
>            && git diff --unified=1 FETCH_HEAD -- .
> ```
>
> Let me know if you want to see the output of `tree`, but all the files are found as expected.

Sample diff:

```bash
diff --git a/.github/workflows/ci.yml b/.github/workflows/ci.yml
index 7c0e612..e4ddca1 100644
--- a/.github/workflows/ci.yml
+++ b/.github/workflows/ci.yml
@@ -75,2 +75,17 @@ jobs:
         run: docker exec $CONTAINER_NAME yarn lint
+
+      - name: Debug CI in container
+        run: |
+          docker exec $CONTAINER_NAME \
+            yum install -y tree \
+            && tree -a . \
+            && git fetch origin dev --depth=1000 \
+            && git diff --unified=1 FETCH_HEAD -- .
+
+      - name: Debug CI on host
+        run: |
+          sudo apt-get install -y tree \
+            && tree -a . \
+            && git fetch origin dev --depth=1000 \
+            && git diff --unified=1 FETCH_HEAD -- .
```

</details>

If it makes a difference this is from a PR where a feature branch is getting merged into `dev`. We use `master` as our default branch. Also, we haven't yet run this action on `master` so don't yet have the `python-coverage-comment-action-data` branch.

Unfortunately this is in a private work repo so I can't give links, but let me know if you need any more info.

Cheers,
Andrew.

### Additional contract requirements

- A valid diff hunk with no added lines, such as a deletion-only hunk, must not cause an assertion failure because no destination filename is available. Parsing must continue so that added lines in later hunks are collected.
