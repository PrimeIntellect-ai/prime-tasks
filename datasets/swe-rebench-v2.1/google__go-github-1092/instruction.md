ProjectCard is not supported for issue timeline
Project card fields from the starfox preview was added for IssueEvent (https://github.com/google/go-github/pull/1066/files). It's still not present for issue timeline though.

See https://developer.github.com/v3/issues/timeline/#list-events-for-an-issue

### Additional contract requirements

Listing an issue timeline requests the timeline and ProjectCard preview representations. Issue timeline responses that include a `project_card` must expose its data as a ProjectCard on the corresponding timeline entry. `Timeline` also provides a nil-safe `GetProjectCard() *ProjectCard` accessor: it returns the entry's card, or nil when the receiver or card is nil.
