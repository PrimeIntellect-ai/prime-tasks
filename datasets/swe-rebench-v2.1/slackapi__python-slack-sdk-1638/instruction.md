Custom Values passed into correctly into Bot/Installation class when cloned during token rotation
(Filling out the following details about bugs will help us solve your issue sooner.)

### Reproducible in:

```bash
pip freeze | grep slack
python --version
sw_vers && uname -v # or `ver`
```

#### The Slack SDK version

```bash
slack_bolt==1.22.0
slack_sdk==3.34.0
```

#### Python runtime version

```bash
Python 3.11.11
```

#### OS info

```bash
ProductName:		macOS
ProductVersion:		14.0
BuildVersion:		23A344
Darwin Kernel Version 23.0.0: Fri Sep 15 14:43:05 PDT 2023; root:xnu-10002.1.13~1/RELEASE_ARM64_T6020
```

#### Steps to reproduce:

1. Custom implementation of InstallationStore using `custom_values` + `token_rotation` enabled
2. During `token_rotation` if custom_values exists, this line: https://github.com/slackapi/python-slack-sdk/blob/main/slack_sdk/oauth/token_rotation/rotator.py#L88 fails because it tries to pass the custom_values which in my case are the `dict` of values. The `Bot` class doesn't expect certain values.


### Expected result:

Expect the Bot to be cloned with custom values correctly.

https://github.com/slackapi/python-slack-sdk/blob/main/slack_sdk/oauth/installation_store/models/bot.py#L90

Seems to merge the entries into a flat dictionary so that when it is passed into the `Bot(**bot.to_dict())` it passes all the key/value pairs. [HIDDEN]

Original
```
  def to_dict(self) -> Dict[str, Any]:
        standard_values = {
            "app_id": self.app_id,
            "enterprise_id": self.enterprise_id,
            "enterprise_name": self.enterprise_name,
            "team_id": self.team_id,
            "team_name": self.team_name,
            "bot_token": self.bot_token,
            "bot_id": self.bot_id,
            "bot_user_id": self.bot_user_id,
            "bot_scopes": ",".join(self.bot_scopes) if self.bot_scopes else None,
            "bot_refresh_token": self.bot_refresh_token,
            "bot_token_expires_at": (
                datetime.utcfromtimestamp(self.bot_token_expires_at) if self.bot_token_expires_at is not None else None
            ),
            "is_enterprise_install": self.is_enterprise_install,
            "installed_at": datetime.utcfromtimestamp(self.installed_at),
        }
        # prioritize standard_values over custom_values
        # when the same keys exist in both
        return {**self.custom_values, **standard_values}
```

Potential Fix
```
  def to_dict(self) -> Dict[str, Any]:
        standard_values = {
            "app_id": self.app_id,
            "enterprise_id": self.enterprise_id,
            "enterprise_name": self.enterprise_name,
            "team_id": self.team_id,
            "team_name": self.team_name,
            "bot_token": self.bot_token,
            "bot_id": self.bot_id,
            "bot_user_id": self.bot_user_id,
            "bot_scopes": ",".join(self.bot_scopes) if self.bot_scopes else None,
            "bot_refresh_token": self.bot_refresh_token,
            "bot_token_expires_at": (
                datetime.utcfromtimestamp(self.bot_token_expires_at) if self.bot_token_expires_at is not None else None
            ),
            "is_enterprise_install": self.is_enterprise_install,
            "installed_at": datetime.utcfromtimestamp(self.installed_at),
        }
        # prioritize standard_values over custom_values
        # when the same keys exist in both
        [HIDDEN]
```

Which would then allow it to be passed into the `Bot()` class

### Actual result:

Error:
```
Failed to run a middleware (error: Bot.__init__() got an unexpected keyword argument 'id')
File "/app/.venv/lib/python3.11/site-packages/slack_sdk/oauth/token_rotation/rotator.py", line 88, in perform_bot_token_rotation
refreshed_bot = Bot(**bot.to_dict()) # type: ignore
TypeError: Bot.__init__() got an unexpected keyword argument 'id'
```

### Additional contract requirements

- During token rotation, cloned `Bot` and `Installation` instances must preserve their custom values as custom values.
- Custom values whose keys match standard attribute names must remain available as custom values without replacing the corresponding standard attribute values.
