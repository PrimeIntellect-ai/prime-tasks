Unnamed add_periodic_task unexpectedly override another periodic task
<!--
Please fill this template entirely and do not erase parts of it.
We reserve the right to close without a response
enhancement requests which are incomplete.
-->
# Checklist
<!--
To check an item on the list replace [ ] with [x].
-->

- [ ] I have checked the [issues list](https://github.com/celery/celery/issues?q=is%3Aissue+label%3A%22Issue+Type%3A+Enhancement%22+-label%3A%22Category%3A+Documentation%22)
  for similar or identical enhancement to an existing feature.
- [ ] I have checked the [pull requests list](https://github.com/celery/celery/pulls?q=is%3Apr+label%3A%22Issue+Type%3A+Enhancement%22+-label%3A%22Category%3A+Documentation%22)
  for existing proposed enhancements.
- [ ] I have checked the [commit log](https://github.com/celery/celery/commits/main)
  to find out if the if the same enhancement was already implemented in the
  main branch.
- [ ] I have included all related issues and possible duplicate issues in this issue
      (If there are none, check this box anyway).

## Related Issues and Possible Duplicates
<!--
Please make sure to search and mention any related issues
or possible duplicates to this issue as requested by the checklist above.

This may or may not include issues in other repositories that the Celery project
maintains or other repositories that are dependencies of Celery.

If you don't know how to mention issues, please refer to Github's documentation
on the subject: https://help.github.com/en/articles/autolinked-references-and-urls#issues-and-pull-requests
-->

#### Related Issues

- Somewhat related #2834

#### Possible Duplicates

- None

# Brief Summary
<!--
Please include a brief summary of what the enhancement is
and why it is needed.
-->

Adding the same periodic task twice with different schedules unexpectedly override the first one.

```python
sig = add.s(2, 2)
app.add_periodic_task(10, sig)
app.add_periodic_task(20, sig)
assert len(app.conf.beat_schedule) == 1
```

# Design

## Architectural Considerations
<!--
If more components other than Celery are involved,
describe them here and the effect it would have on Celery.
-->
None

## Proposed Behavior
<!--
Please describe in detail how this enhancement is going to change the behavior
of an existing feature.
Describe what happens in case of failures as well if applicable.
-->

Now I understand that I can just set a name explicitly to avoid the behavior, but it is not clear in the docs and looks like it could be warned/failed in runtime to improve developer experience.

## Proposed UI/UX
<!--
Please provide your ideas for the API, CLI options,
configuration key names etc. that will be adjusted for this enhancement.
-->

## Diagrams
<!--
Please include any diagrams that might be relevant
to the implementation of this enhancement such as:
* Class Diagrams
* Sequence Diagrams
* Activity Diagrams
You can drag and drop images into the text box to attach them to this issue.
-->
N/A

## Alternatives
<!--
If you have considered any alternative implementations
describe them in detail below.
-->
None

### Additional contract requirements

- When adding an unnamed periodic task whose generated key is already in use, Celery must surface the collision at runtime by logging a warning or raising an error; silently replacing the existing entry is not acceptable.
- Giving same-signature periodic tasks distinct explicit names allows them to be registered as separate schedule entries without a collision.
