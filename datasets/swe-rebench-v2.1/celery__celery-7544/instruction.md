Celery worker dies, but has an exit code of 0
<!--
Please fill this template entirely and do not erase parts of it.
We reserve the right to close without a response
bug reports which are incomplete.
-->
# Checklist
<!--
To check an item on the list replace [ ] with [x].
-->
- [ ] I have verified that the issue exists against the `master` branch of Celery.
- [ ] This has already been asked to the [discussions forum](https://github.com/celery/celery/discussions) first.
- [ ] I have read the relevant section in the
  [contribution guide](http://docs.celeryproject.org/en/latest/contributing.html#other-bugs)
  on reporting bugs.
- [x] I have checked the [issues list](https://github.com/celery/celery/issues?q=is%3Aissue+label%3A%22Issue+Type%3A+Bug+Report%22+-label%3A%22Category%3A+Documentation%22)
  for similar or identical bug reports.
- [x] I have checked the [pull requests list](https://github.com/celery/celery/pulls?q=is%3Apr+label%3A%22PR+Type%3A+Bugfix%22+-label%3A%22Category%3A+Documentation%22)
  for existing proposed fixes.
- [x] I have checked the [commit log](https://github.com/celery/celery/commits/master)
  to find out if the bug was already fixed in the master branch.
- [x] I have included all related issues and possible duplicate issues
  in this issue (If there are none, check this box anyway).

## Mandatory Debugging Information

- [x] I have included the output of ``celery -A proj report`` in the issue.
```

```
- [ ] I have verified that the issue exists against the `master` branch of Celery.
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
**Celery version**: 5.2.3 (dawn-chorus)
<!-- Include the output of celery -A proj report below -->
<details>
<summary><b><code>celery report</code> Output:</b></summary>
<p>

```
software -> celery:5.2.3 (dawn-chorus) kombu:5.2.3 py:3.9.10
            billiard:3.6.4.0 py-amqp:5.0.9
platform -> system:Darwin arch:64bit
            kernel version:20.6.0 imp:CPython
loader   -> celery.loaders.app.AppLoader
settings -> transport:amqp results:django-db
```

</p>
</details>

# Steps to Reproduce

## Required Dependencies
<!-- Please fill the required dependencies to reproduce this issue -->
* **Minimal Python Version**: N/A or Unknown
* **Minimal Celery Version**: N/A or Unknown
* **Minimal Kombu Version**: N/A or Unknown
* **Minimal Broker Version**: N/A or Unknown
* **Minimal Result Backend Version**: N/A or Unknown
* **Minimal OS and/or Kernel Version**: N/A or Unknown
* **Minimal Broker Client Version**: N/A or Unknown
* **Minimal Result Backend Client Version**: N/A or Unknown

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
-->

<details>
<p>

```python
```

</p>
</details>

# Expected Behavior

Expected worker to exit with a non-zero code

# Actual Behavior

Ran celery with the following settings
```
CELERY_BROKER_CONNECTION_RETRY = False
CELERY_BROKER_CONNECTION_TIMEOUT = 2 # seconds
```
because for kubernetes related reasons it's better for us if the workers just die immediately if the config is wrong.

The worker does exit fast enough, but the exit code is 0 despite the following backtrace
```
[2022-03-18 17:33:30,670: CRITICAL/MainProcess] Unrecoverable error: ConnectionRefusedError(61, 'Connection refused')
Traceback (most recent call last):
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/celery/worker/worker.py", line 203, in start
    self.blueprint.start(self)
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/celery/bootsteps.py", line 116, in start
    step.start(parent)
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/celery/bootsteps.py", line 365, in start
    return self.obj.start()
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/celery/worker/consumer/consumer.py", line 326, in start
    blueprint.start(self)
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/celery/bootsteps.py", line 116, in start
    step.start(parent)
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/celery/worker/consumer/connection.py", line 21, in start
    c.connection = c.connect()
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/celery/worker/consumer/consumer.py", line 422, in connect
    conn = self.connection_for_read(heartbeat=self.amqheartbeat)
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/celery/worker/consumer/consumer.py", line 428, in connection_for_read
    return self.ensure_connected(
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/celery/worker/consumer/consumer.py", line 451, in ensure_connected
    conn.connect()
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/kombu/connection.py", line 275, in connect
    return self._ensure_connection(
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/kombu/connection.py", line 434, in _ensure_connection
    return retry_over_time(
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/kombu/utils/functional.py", line 312, in retry_over_time
    return fun(*args, **kwargs)
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/kombu/connection.py", line 878, in _connection_factory
    self._connection = self._establish_connection()
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/kombu/connection.py", line 813, in _establish_connection
    conn = self.transport.establish_connection()
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/kombu/transport/pyamqp.py", line 201, in establish_connection
    conn.connect()
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/amqp/connection.py", line 323, in connect
    self.transport.connect()
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/amqp/transport.py", line 113, in connect
    self._connect(self.host, self.port, self.connect_timeout)
  File "/Users/tomparker-shemilt/.virtualenvs/case-cards/lib/python3.9/site-packages/amqp/transport.py", line 197, in _connect
    self.sock.connect(sa)
ConnectionRefusedError: [Errno 61] Connection refused
```

I tried messing around with locally editing https://github.com/celery/celery/blob/master/celery/bin/worker.py and noted the
```
        worker.start()
        [HIDDEN]
    except SecurityError as e:
        ctx.obj.error(e.args[0])
        ctx.exit(1)
```

block at the end. [HIDDEN]
