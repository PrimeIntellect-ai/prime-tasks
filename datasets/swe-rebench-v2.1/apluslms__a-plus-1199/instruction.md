The next submitter link for manual assessment
After merging the PR #1167 for the issue #1110, we found bugs in the new implementation. The pull request #1167 includes more comments about the details.


* The selected next submitter may be such a student who has already received manual grading on a submission other than the latest one. A student should be considered manually graded once any one of his/her submissions has been manually graded. The "next submitter" link should not repeat a student who has been manually graded.
* The "next submitter" link may repeat the same student who was already being inspected. This happens when the student's earlier submission (but not the latest) has been manually graded even though other students have not received any manual grading.
* When all students have received manual grading, the "next submitter" link must stop cycling between students like the old implementation had done. The old code has an if statement with the comment "There are no more unassessed submitters". It redirects back to the submission list.

_Originally posted by @Mankro in https://github.com/apluslms/a-plus/pull/1167#pullrequestreview-1474236719_

### Additional contract requirements

- Eligible submitters are ordered by the time of their earliest submission for the exercise, earliest first; with a `prev` user ID, select the next eligible submitter in that order.
