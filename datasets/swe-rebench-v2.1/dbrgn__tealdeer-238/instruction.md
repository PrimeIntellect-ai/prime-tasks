Custom patches should not need to be formatted like a full page
Quote from PR #142 discussion:
> Another issue for a new PR: Right now the patches need to be formatted like a full page, including a heading. Otherwise, the first line is interpreted as the heading, and skipped when printing ([HIDDEN]). However, I think that too can be fixed in a separate PR, I don't want to hold up this PR too long.

Pre-requisites:
* Issue #180

Acceptance Criteria:
* Format of .patch files should be expected to not have a heading
* Update tests to reflect this change
