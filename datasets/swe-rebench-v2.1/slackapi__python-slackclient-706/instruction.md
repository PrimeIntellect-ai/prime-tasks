WebClient's paginated API calls may fail with no params (v2.6.0+)
### Description

Since version 2.6.0, `WebClient` w/ `run_async=False` may fail during paginated API calls only when the call doesn't have any params.

```python
from slack import WebClient
client = WebClient(token="xoxb-***")
all = []
for page in client.conversations_list():
    all = all + page["channels"] # only when there are 100+ channels in the workspace
```

```
  File "/path-to-project/env/lib/python3.8/site-packages/slack/web/slack_response.py", line 134, in __next__
    [HIDDEN]
AttributeError: 'NoneType' object has no attribute 'update'
```

### What type of issue is this? (place an `x` in one of the `[ ]`)
- [x] bug
- [ ] enhancement (feature request)
- [ ] question
- [ ] documentation related
- [ ] testing related
- [ ] discussion

### Requirements (place an `x` in each of the `[ ]`)
* [x] I've read and understood the [Contributing guidelines](https://github.com/slackapi/python-slackclient/blob/master/.github/contributing.md) and have done my best effort to follow them.
* [x] I've read and agree to the [Code of Conduct](https://slackhq.github.io/code-of-conduct).
* [x] I've searched for any related issues and avoided creating a duplicate issue.

---

### Bug Report

#### Reproducible in:

* slackclient version: v2.6.0+
* python version: any
* OS version(s): any

#### Steps to reproduce:

```python
from slack import WebClient
client = WebClient(token="xoxb-***")
all = []
for page in client.conversations_list():
    all = all + page["channels"] # only when there are 100+ channels in the workspace
```

```
  File "/path-to-project/env/lib/python3.8/site-packages/slack/web/slack_response.py", line 134, in __next__
    [HIDDEN]
AttributeError: 'NoneType' object has no attribute 'update'
```

#### Expected result:

Successful pagination.

#### Actual result:

`WebClient` raises an error when fetching the second page.
