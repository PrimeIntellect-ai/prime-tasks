Pydantic model containing UUID4 between tasks in chain() fails validation
<!--
Please fill this template entirely and do not erase parts of it.
We reserve the right to close without a response
bug reports which are incomplete.
-->
# Checklist
<!--
To check an item on the list replace [ ] with [x].
-->
- [x] I have verified that the issue exists against the `main` branch of Celery.
- [ ] This has already been asked to the [discussions forum](https://github.com/celery/celery/discussions) first.
- [x] I have read the relevant section in the
  [contribution guide](https://docs.celeryq.dev/en/main/contributing.html#other-bugs)
  on reporting bugs.
- [x] I have checked the [issues list](https://github.com/celery/celery/issues?q=is%3Aissue+label%3A%22Issue+Type%3A+Bug+Report%22+-label%3A%22Category%3A+Documentation%22)
  for similar or identical bug reports.
- [x] I have checked the [pull requests list](https://github.com/celery/celery/pulls?q=is%3Apr+label%3A%22PR+Type%3A+Bugfix%22+-label%3A%22Category%3A+Documentation%22)
  for existing proposed fixes.
- [x] I have checked the [commit log](https://github.com/celery/celery/commits/main)
  to find out if the bug was already fixed in the main branch.
- [x] I have included all related issues and possible duplicate issues
  in this issue (If there are none, check this box anyway).
- [ ] I have tried to reproduce the issue with [pytest-celery](https://docs.celeryq.dev/projects/pytest-celery/en/latest/userguide/celery-bug-report.html) and added the reproduction script below.

## Mandatory Debugging Information

- [x] I have included the output of ``celery -A proj report`` in the issue.
    (if you are not able to do this, then at least specify the Celery
     version affected).
- [x] I have verified that the issue exists against the `main` branch of Celery.
- [x] I have included the contents of ``pip freeze`` in the issue.
- [x] I have included all the versions of all the external dependencies required
  to reproduce this bug.

## Optional Debugging Information
<!--
Try some of the below if you think they are relevant.
It will help us figure out the scope of the bug and how many users it affects.
-->
- [ ] I have tried reproducing the issue on more than one Python version
  and/or implementation.
- [ ] I have tried reproducing the issue on more than one message broker and/or
  result backend.
- [ ] I have tried reproducing the issue on more than one version of the message
  broker and/or result backend.
- [ ] I have tried reproducing the issue on more than one operating system.
- [ ] I have tried reproducing the issue on more than one workers pool.
- [ ] I have tried reproducing the issue with autoscaling, retries,
  ETA/Countdown & rate limits disabled.
- [ ] I have tried reproducing the issue after downgrading
  and/or upgrading Celery and its dependencies.

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

- None

#### Possible Duplicates

- None

## Environment & Settings
<!-- Include the contents of celery --version below -->
**Celery version**:
<!-- Include the output of celery -A proj report below -->
<details>
<summary><b><code>celery report</code> Output:</b></summary>
<p>

```
software -> celery:5.5.0rc1 (immunity) kombu:5.4.2 py:3.11.2
            billiard:4.2.1 redis:5.1.1
platform -> system:Linux arch:64bit, ELF
            kernel version:6.1.0-25-amd64 imp:CPython
loader   -> celery.loaders.app.AppLoader
settings -> transport:redis results:redis

broker_url: 'redis://localhost:6379/0'
result_backend: 'redis'
deprecated_settings: None

```

</p>
</details>

# Steps to Reproduce

## Required Dependencies
<!-- Please fill the required dependencies to reproduce this issue -->
- **Minimal Python Version**: py3.11
- **Minimal Celery Version**: 5.5.0b4
- **Minimal Kombu Version**: N/A or Unknown
- **Minimal Broker Version**: N/A or Unknown
- **Minimal Result Backend Version**: N/A or Unknown
- **Minimal OS and/or Kernel Version**: N/A or Unknown
- **Minimal Broker Client Version**: N/A or Unknown
- **Minimal Result Backend Client Version**: N/A or Unknown

### Python Packages
<!-- Please fill the contents of pip freeze below -->
<details>
<summary><b><code>pip freeze</code> Output:</b></summary>
<p>

```
amqp==5.2.0
annotated-types==0.7.0
async-timeout==4.0.3
billiard==4.2.1
celery==5.5.0rc1
click==8.1.7
click-didyoumean==0.3.1
click-plugins==1.1.1
click-repl==0.3.0
kombu==5.4.2
prompt_toolkit==3.0.48
pydantic==2.9.2
pydantic_core==2.23.4
python-dateutil==2.9.0.post0
redis==5.1.1
six==1.16.0
typing_extensions==4.12.2
tzdata==2024.2
vine==5.1.0
wcwidth==0.2.13
```

</p>
</details>

### Other Dependencies
<!--
Please provide system dependencies, configuration files
and other dependency information if applicable
-->
<details>
<p>
N/A
</p>
</details>

## Minimally Reproducible Test Case
<!--
Please provide a reproducible test case.
Refer to the Reporting Bugs section in our contribution guide.

We prefer submitting test cases in the form of a PR to our integration test suite.
If you can provide one, please mention the PR number below.
If not, please attach the most minimal code example required to reproduce the issue below.
If the test case is too large, please include a link to a gist or a repository below.

Alternatively, the pytest-celery plugin can be used to create standalone reproduction scripts
that can be added to this report. See the pytest-celery documentation for more information at
pytest-celery.readthedocs.io
-->

Full test case: https://github.com/dromer/celery_pydantic_test


# Expected Behavior
I would expect the `return payload` in `task1` to not cause errors on the `uuid` property.

# Actual Behavior
When we chain the commands we get a failed validation if we rely on the pydantic return annotation:

```python
pydantic_core._pydantic_core.ValidationError: 1 validation error for TestModel
uuid
  Input should be an instance of UUID [type=is_instance_of, input_value='53b3eab5-dbbd-4706-9635-5eec447fbb0c', input_type=str]
    For further information visit https://errors.pydantic.dev/2.9/v/is_instance_of
```
