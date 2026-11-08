Initialize View state field to ViewState object based on type
The View class (`slack_sdk.models.views.View`) does not initialize the state parameter value [HIDDEN] based on the corresponding type (`ViewState` or `dict`, respectively)

### Reproducible in:

#### The Slack SDK version

```
slack-sdk==3.5.1
```

#### Python runtime version

```
Python 3.8.9
```

#### OS info

```
ProductName:    macOS
ProductVersion: 11.3.1
BuildVersion:   20E241
Darwin Kernel Version 20.4.0: Thu Apr 22 21:46:47 PDT 2021; root:xnu-7195.101.2~1/RELEASE_X86_64
```

#### Steps to reproduce:

(Share the commands to run, source code, and project settings (e.g., setup.py))

1. Instantiate a View object with state dict value
2. See below

### Expected result:

`View().state` object field is `ViewState` type and `ViewState.values` is initialized with `ViewStateValue` objects based on state initialization parameter value

### Actual result:

`View().state` field is `dict`, and `ViewState` and `ViewStateValue` objects are not initialized based on state value

### Requirements

For general questions/issues about Slack API platform or its server-side, could you submit questions at https://my.slack.com/help/requests/new instead. :bow:

Please read the [Contributing guidelines](https://github.com/slackapi/python-slack-sdk/blob/main/.github/contributing.md) and [Code of Conduct](https://slackhq.github.io/code-of-conduct) before creating this issue or pull request. By submitting, you are agreeing to those rules.

### Additional contract requirements

- `View` must accept `state` as either a plain dict or an already-constructed `ViewState`. For a dict, `view.state` must be a `ViewState`, and its nested state values must be represented by `ViewStateValue` objects. When a `ViewState` is supplied, `view.state` must remain a `ViewState`.
