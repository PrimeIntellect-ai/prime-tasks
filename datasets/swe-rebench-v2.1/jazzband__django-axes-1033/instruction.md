`AXES_SENSITIVE_PARAMETERS` doesn't affect database handler logs
Hello!
I encountered an issue when attempting to utilize the `AXES_SENSITIVE_PARAMETERS` configuration in order to prevent usernames from being written into our log files, even though I added the setting like so:
```python
AXES_SENSITIVE_PARAMETERS = ["username"]
```
Whenever a login attempt fails a log is still being written:
![image](https://user-images.githubusercontent.com/107052238/221629353-c4cf3263-4e21-4565-941d-f0846bc9843e.png)

I might've misunderstood how it works, but I did some debugging and found the following:
1. Inside `axes.handlers.database.py` some of the WARN logs are being written using the `client_str` variable
2. The `client_str` variable is produced from the `get_client_str` function in `axes.helpers.py`
3. [HIDDEN]

I'd love some feedback whether I misunderstood the usage of this configuration, or is this an actual issue,
Thanks! Shai.

### Additional contract requirements

- `get_client_str` must cleanse values for parameters configured in `AXES_SENSITIVE_PARAMETERS`, rather than expose those values in its returned string.
- When `AXES_SENSITIVE_PARAMETERS` contains `"username"`, `get_client_str` must represent the username in its returned client string as exactly `********************`.
- When `AXES_SENSITIVE_PARAMETERS` contains `username`, database-handler warning logs for a failed login must include `********************` in place of the username.
