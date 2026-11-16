Running worker with --skip-checks option fails with a TypeError
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
- [x] I have tried reproducing the issue on more than one Python version
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

- #7581 (feature request that led to the `--skip-checks` option being added)
- #7859 (PR that added the option)

#### Possible Duplicates

- None

## Environment & Settings
<!-- Include the contents of celery --version below -->
**Celery version**: 5.3.1 (emerald-rush)
<!-- Include the output of celery -A proj report below -->
<details>
<summary><b><code>celery report</code> Output:</b></summary>
<p>

This is on the Docker dev container. The results are not substantially different from the system on which I encountered the failure, aside from a massive and mostly irrelevant Django settings dump.

```
developer@dc2346ef89d6:~/celery$ celery --config t.integration.test_worker_config report

software -> celery:5.3.1 (emerald-rush) kombu:5.3.1 py:3.8.18
            billiard:4.1.0 py-amqp:5.1.1
platform -> system:Linux arch:64bit
            kernel version:5.15.49-linuxkit-pr imp:CPython
loader   -> celery.loaders.default.Loader
settings -> transport:amqp results:disabled

broker_connection_retry: False
broker_connection_retry_on_startup: False
broker_connection_timeout: 0
broker_url: 'amqp://guest:********@foobar:1234//'
worker_log_color: False
worker_redirect_stdouts: False
deprecated_settings: None
```

</p>
</details>

# Steps to Reproduce

Run a worker with the `--skip-checks` option or with`CELERY_SKIP_CHECKS=1` (or any non-empty value) in the environment.

## Required Dependencies
<!-- Please fill the required dependencies to reproduce this issue -->
- **Minimal Python Version**: N/A or Unknown
- **Minimal Celery Version**: 5.3.1 (emerald-rush)
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
alabaster==0.7.13
amqp==5.1.1
async-timeout==4.0.3
attrs==23.1.0
azure-core==1.29.3
azure-storage-blob==12.17.0
Babel==2.12.1
backports.zoneinfo==0.2.1
billiard==4.1.0
boto3==1.28.36
botocore==1.31.36
bump2version==1.0.1
bumpversion==0.6.0
cachetools==5.3.1
cassandra-driver==3.28.0
celery==5.3.1
certifi==2023.7.22
cffi==1.15.1
cfgv==3.4.0
chardet==5.2.0
charset-normalizer==3.2.0
click==8.1.7
click-didyoumean==0.3.0
click-plugins==1.1.1
click-repl==0.3.0
colorama==0.4.6
couchbase==4.1.8
coverage==7.3.0
cryptography==41.0.3
DateTime==5.2
distlib==0.3.7
dnspython==2.4.2
docutils==0.19
elasticsearch==7.17.9
ephem==4.1.4
eventlet==0.33.3
exceptiongroup==1.1.3
filelock==3.12.3
flake8==6.1.0
flake8-docstrings==1.7.0
flakeplus==1.1.0
future==0.18.3
geomet==0.2.1.post1
gevent==23.7.0
greenlet==2.0.2
identify==2.5.27
idna==3.4
imagesize==1.4.1
importlib-metadata==6.8.0
iniconfig==2.0.0
isodate==0.6.1
isort==5.12.0
Jinja2==3.1.2
jmespath==1.0.1
kombu==5.3.1
livereload==2.6.3
MarkupSafe==2.1.3
mccabe==0.7.0
mock==5.1.0
moto==4.2.0
msgpack==1.0.5
mypy==1.5.0
mypy-extensions==1.0.0
nodeenv==1.8.0
packaging==23.1
platformdirs==3.10.0
pluggy==1.3.0
pre-commit==3.3.3
prompt-toolkit==3.0.39
pyArango==2.0.2
pycodestyle==2.11.0
pycouchdb==1.14.2
pycparser==2.21
pycurl==7.45.2
pydocstyle==6.3.0
pydocumentdb==2.3.5
pyflakes==3.1.0
Pygments==2.16.1
pylibmc==1.6.3
pymongo==4.5.0
pyproject-api==1.5.4
pytest==7.4.0
pytest-celery==0.0.0
pytest-click==1.1.0
pytest-cov==4.1.0
pytest-github-actions-annotate-failures==0.2.0
pytest-order==1.1.0
pytest-rerunfailures==12.0
pytest-subtests==0.11.0
pytest-timeout==2.1.0
python-consul2==0.1.5
python-dateutil==2.8.2
python-memcached==1.59
pytz==2023.3
PyYAML==6.0.1
redis==4.6.0
requests==2.31.0
responses==0.23.3
s3transfer==0.6.2
six==1.16.0
snowballstemmer==2.2.0
softlayer-messaging==1.0.3
Sphinx==5.3.0
sphinx-autobuild==2021.3.14
sphinx-celery==2.0.0
sphinx-click==4.4.0
sphinx-testing==1.0.1
sphinx2rst==1.1.0
sphinxcontrib-applehelp==1.0.4
sphinxcontrib-devhelp==1.0.2
sphinxcontrib-htmlhelp==2.0.1
sphinxcontrib-jsmath==1.0.1
sphinxcontrib-qthelp==1.0.3
sphinxcontrib-serializinghtml==1.1.5
SQLAlchemy==2.0.20
tblib==2.0.0
tomli==2.0.1
tornado==6.3.3
tox==4.10.0
types-PyYAML==6.0.12.11
typing_extensions==4.7.1
tzdata==2023.3
Unipath==1.1
urllib3==1.26.16
vine==5.0.0
virtualenv==20.24.3
wcwidth==0.2.6
Werkzeug==2.3.7
xmltodict==0.13.0
zipp==3.16.2
zope.event==5.0
zope.interface==6.0
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
In a shell opened with `docker compose run --rm celery bash`, the following illustrates the failure.

```
developer@dc2346ef89d6:~/celery$ celery --skip-checks --config t.integration.test_worker_config report
Traceback (most recent call last):
  File "/home/developer/.pyenv/versions/3.8.18/bin/celery", line 8, in <module>
    sys.exit(main())
  File "/home/developer/celery/celery/__main__.py", line 15, in main
    sys.exit(_main())
  File "/home/developer/celery/celery/bin/celery.py", line 235, in main
    return celery(auto_envvar_prefix="CELERY")
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 1157, in __call__
    return self.main(*args, **kwargs)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 1078, in main
    rv = self.invoke(ctx)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 1685, in invoke
    super().invoke(ctx)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 1434, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 783, in invoke
    return __callback(*args, **kwargs)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/decorators.py", line 33, in new_func
    return f(get_current_context(), *args, **kwargs)
  File "/home/developer/celery/celery/bin/celery.py", line 161, in celery
    [HIDDEN]
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/os.py", line 680, in __setitem__
    value = self.encodevalue(value)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/os.py", line 750, in encode
    raise TypeError("str expected, not %s" % type(value).__name__)
TypeError: str expected, not bool
```

Alternatively, for any non-empty value of `CELERY_SKIP_CHECKS`, same result:
```
developer@dc2346ef89d6:~/celery$ CELERY_SKIP_CHECKS=1 celery --config t.integration.test_worker_config worker
Traceback (most recent call last):
  File "/home/developer/.pyenv/versions/3.8.18/bin/celery", line 8, in <module>
    sys.exit(main())
  File "/home/developer/celery/celery/__main__.py", line 15, in main
    sys.exit(_main())
  File "/home/developer/celery/celery/bin/celery.py", line 235, in main
    return celery(auto_envvar_prefix="CELERY")
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 1157, in __call__
    return self.main(*args, **kwargs)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 1078, in main
    rv = self.invoke(ctx)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 1685, in invoke
    super().invoke(ctx)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 1434, in invoke
    return ctx.invoke(self.callback, **ctx.params)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/core.py", line 783, in invoke
    return __callback(*args, **kwargs)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/site-packages/click/decorators.py", line 33, in new_func
    return f(get_current_context(), *args, **kwargs)
  File "/home/developer/celery/celery/bin/celery.py", line 161, in celery
    [HIDDEN]
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/os.py", line 680, in __setitem__
    value = self.encodevalue(value)
  File "/home/developer/.pyenv/versions/3.8.18/lib/python3.8/os.py", line 750, in encode
    raise TypeError("str expected, not %s" % type(value).__name__)
TypeError: str expected, not bool
```

</p>
</details>

# Expected Behavior
<!-- Describe in detail what you expect to happen -->
Expected either the `CELERY_SKIP_CHECKS=1` or the `--skip-checks` option to start up the celery worker with Django's initial checks disabled. In the context of the minimal test case, Celery should start up, show its welcome message, then exit with error due to inability to contact the message broker.

# Actual Behavior
<!--
Describe in detail what actually happened.
Please include a backtrace and surround it with triple backticks (```).
In addition, include the Celery daemon logs, the broker logs,
the result backend logs and system logs below if they will help us debug
the issue.
-->
Celery immediately exits with a `TypeError`. See the minimally reproducible test case section for backtraces.
