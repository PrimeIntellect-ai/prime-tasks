github_release_report errors if ANY release  is missing notes
### Describe the bug

Task github_release_report throw an error `Error: 'NoneType' object has no attribute 'splitlines'` when trying to parse the Release Body if any release in all of the repo history has a blank body.

To make this worse, blank body is the default behavior of the github_release task so it is very, very easy to hit this situation and make the report useless

### Reproduction steps

1. Use `cci task run github_release` to create a release
2. attempt to report on it with `cci task run github_release_report`

EXPECTED: report to run
ACTUAL: `Error: 'NoneType' object has no attribute 'splitlines'`


### Your CumulusCI and Python versions

CumulusCI version: 3.77.0 (/Users/kai.amundsen/.local/bin/cci)
Python version: 3.10.9 (/Users/kai.amundsen/.local/pipx/venvs/cumulusci/bin/python)


### Operating System

macOS 13.4.1

### Windows environment

_No response_

### CumulusCI installation method

pipx

### Error Gist

_No response_

### Additional information

_No response_

### Additional contract requirements

- A release with a missing body must still appear in `task.return_values["releases"]`. For the release tagged `rel/2.1`, its entry must be `{"beta": False, "name": "1.0", "tag": "rel/2.1", "time_created": datetime(2018, 1, 2, 0, 0, tzinfo=pytz.UTC), "time_push_production": None, "time_push_sandbox": None, "url": ""}`.
