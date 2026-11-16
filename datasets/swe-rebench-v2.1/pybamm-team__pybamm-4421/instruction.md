Rename `set_events`
As discussed in the PR #4254, `set_event` should be renamed because of misleading.

              This adds a side effect to what would be expected to be a simple setter. At minimum it should be changed to `append_events()` or `add_events()`. Was there an actual bug that this was fixing or just not sure if it would cause issues?

_Originally posted by @kratman in https://github.com/pybamm-team/PyBaMM/pull/4254#discussion_r1672332716_
