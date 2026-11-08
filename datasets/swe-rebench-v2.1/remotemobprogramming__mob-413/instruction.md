mob status should show if a mob session exists
It would be helpful when `mob status` shows if a mob session exists on the current branch, when not on a mob branch, to look up if a remote mob branch already exists.

Something like this:

    ➜  myProject git:(main) mob status
    > you are on base branch 'main'
    > wip branch 'mob/main' contains 7 commits. The last 5 were:
    > 38209edb 6 hours ago <Wanda Hess>
    > 2359e605 5 hours ago <Ross Carter>
    > 3868b5c6 5 hours ago <Claudia Osborne>
    > b848355a 5 hours ago <Lee Klein>
    > 209e8bb2 5 hours ago <Ammar Carlson>

### Additional contract requirements

- When listing a detected remote wip branch, show its relative age in parentheses, ending with the exact text ` ago)`.
- When remote wip branches are detected, print the exact header `remote wip branches detected:` followed by an entry for every detected branch on a new line prefixed with `  - `; display the branch name (for example, `origin/mob-session`) and its relative age in parentheses, including ` second` and ending with ` ago)`.
