SecureSerializer fails on certain types and binary serializers
<!--
Please fill this template entirely and do not erase parts of it.
We reserve the right to close without a response
bug reports which are incomplete.
-->
# Checklist
<!--
To check an item on the list replace [ ] with [x].
-->
- [X] I have verified that the issue exists against the `main` branch of Celery.
- [ ] This has already been asked to the [discussions forum](https://github.com/celery/celery/discussions) first.
- [X] I have read the relevant section in the
  [contribution guide](https://docs.celeryq.dev/en/main/contributing.html#other-bugs)
  on reporting bugs.
- [X] I have checked the [issues list](https://github.com/celery/celery/issues?q=is%3Aissue+label%3A%22Issue+Type%3A+Bug+Report%22+-label%3A%22Category%3A+Documentation%22)
  for similar or identical bug reports.
- [X] I have checked the [pull requests list](https://github.com/celery/celery/pulls?q=is%3Apr+label%3A%22PR+Type%3A+Bugfix%22+-label%3A%22Category%3A+Documentation%22)
  for existing proposed fixes.
- [X] I have checked the [commit log](https://github.com/celery/celery/commits/main)
  to find out if the bug was already fixed in the main branch.
- [X] I have included all related issues and possible duplicate issues
  in this issue (If there are none, check this box anyway).
- [X] I have tried to reproduce the issue with [pytest-celery](https://docs.celeryq.dev/projects/pytest-celery/en/latest/userguide/celery-bug-report.html) and added the reproduction script below.

## Mandatory Debugging Information

- [ ] I have included the output of ``celery -A proj report`` in the issue.
    (if you are not able to do this, then at least specify the Celery
     version affected).
- [X] I have verified that the issue exists against the `main` branch of Celery.
- [ ] I have included the contents of ``pip freeze`` in the issue.
- [ ] I have included all the versions of all the external dependencies required
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
```

</p>
</details>

# Steps to Reproduce

## Required Dependencies
<!-- Please fill the required dependencies to reproduce this issue -->
- **Minimal Python Version**: N/A or Unknown
- **Minimal Celery Version**: N/A or Unknown
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

<details>
<p>

```python

app.conf.update(
    security_key='/private/keys/celery/private.key',
    security_certificate='/private/keys/celery/public.pem',
    security_cert_store='/private/keys/celery/*.pem')

app.setup_security()

@app.task
def serializer_test_task(arg: Any) -> Any:
    return arg

def test_serialize(data):
    res = serializer_test_task.delay(data)
    deserialized_value = res.get()
    assert deserialized_value == data

test_serialize(data=b"foo") # fails to validate signature

#############

app.setup_security(serializer="pickle")
test_serialize(data="foo") # fails to serialize any value using pickle serializer

```

</p>
</details>

# Expected Behavior


# Actual Behavior

There are several bugs in the SecureSerializer feature:
 - When using the 'json' serializer (default), it will always fail to validate the signature if the passed value is of type 'bytes'
- When using the other binary serializer (and not a string-based serializer like 'json'), for example 'pickle', the serializer is completely broken.
