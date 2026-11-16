[BUG] Unable to authenticate SMTP due to inability to set username
**Describe the bug**
Arguably in-between a bug/feature request but I'd class it as a problem with existing functionality rather than a request for new functionality, so I'm choosing bug! I'm not able to use SMTP notifications because my SMTP provider pre-generates usernames to be a random alphanumeric string rather than an email address, and the config.yaml file only allows me to input sender/receiver email addresses and not the username for smtp auth.

**To Reproduce**
Steps to reproduce the behavior: Try to use AWS SES or any other similar SMTP provider with this project

**Expected behavior**
I'm able to customise the SMTP username to be different than the sender email address.

Below is what I'd expect the SMTP section of the config.yaml file to look like:

```
email: "example@example.com"
# username: "" # Uncomment this if your SMTP username is different than your sender address
# to: "email@domain.com" # Uncomment this if you'd like to send notifications to a different email address than your sender address
password: ""
host: ""
port: 587
# no_tls: true # Uncomment this if your SMTP provider doesn't support TLS
```

### Additional contract requirements

- The SMTP username is configured under the `app.smtp.username` key.
- Add a public function `get_smtp_username(config)` in module `src.config_parser` that returns the configured SMTP username string when present, or `None` when the key is missing.


- - The notification message must include `Subject: icloud-docker: Two step authentication required`.
