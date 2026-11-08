MFA Token not being cached
### Describe the bug
I'm trying to get Snowflake's [DUO-based MFA](https://docs.snowflake.com/en/user-guide/security-mfa.html#connecting-to-snowflake-with-mfa) working when running dbt in a linux container running on my laptop.  Technically it works, but it's not caching the token and I have to repeatedly re-authorize.  I have tried:

* Setting ALLOW_CLIENT_MFA_CACHING to true for the account
* Setting ALLOW_ID_TOKEN to true for the account
* Setting `authenticator: username_password_mfa` in profiles.yml

All that, and yet, every time I run dbt, I get 4 MFA auth requests right away, and then 1 for each model that it runs.  Obviously, this is impractical with 10-100's of models.  I'm wondering what else I might be missing, if anything.  I swear there used to be a note in Snowflake's docs that some aspect of this only worked on Mac and Windows environments, but I can't find that anymore and was hopeful that it had been resolved for linux.  Perhaps this is a dbt defect that isn't sending the right auth method to the python lib?


### System information
**The output of `dbt --version`:**
```
root@bbafbba2e1dc:/dbt-runner/dbt# dbt --version
installed version: 0.21.0
   latest version: 0.21.1

Your version of dbt is out of date! You can find instructions for upgrading here:
https://docs.getdbt.com/docs/installation

Plugins:
  - snowflake: 0.21.0
```

**The operating system you're using:**  Using a linux container built based on [this dockerfile](https://github.com/gnilrets/dbt-container-skeleton/blob/main/Dockerfile) (with some minor modifications)
```
root@bbafbba2e1dc:/dbt-runner/dbt# cat /etc/os-release
PRETTY_NAME="Debian GNU/Linux 11 (bullseye)"
NAME="Debian GNU/Linux"
VERSION_ID="11"
VERSION="11 (bullseye)"
VERSION_CODENAME=bullseye
ID=debian
HOME_URL="https://www.debian.org/"
SUPPORT_URL="https://www.debian.org/support"
BUG_REPORT_URL="https://bugs.debian.org/"


root@bbafbba2e1dc:/dbt-runner/dbt# uname -r
5.10.47-linuxkit
```

**The output of `python --version`:**
```
root@bbafbba2e1dc:/dbt-runner/dbt# python --version
Python 3.8.12
```
**Version of snowflake connector:** `snowflake-connector-python[secure-local-storage]==2.5.1`

### Additional contract requirements

- When an authenticator is configured, the connection parameters passed to the Snowflake connector include `client_request_mfa_token=True`, enabling MFA token requesting and caching.
