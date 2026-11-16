Improve `slack-access-token` pattern.
**Is your feature request related to a problem? Please describe.**
The current Slack access token pattern is quite simple and thus prone to false-positives.

https://github.com/gitleaks/gitleaks/blob/839f114f2b2ca9429300e545aa5c93a2caf2e3d8/config/gitleaks.toml#L2602-L2608

It checks for strings with the prefix `xoxp-` followed by at least 10 alphanumeric characters, which tends to flag placeholders like `xoxp-yourtokenhere`. Actual Slack access tokens have multiple segments (e.g. `xoxb-17653672481-19874698323-pdFZKVeTuE8sk7oOcBrzbqgy`), so it should be straightforward to increase the accuracy of this pattern by looking for that.


cc @zricethezav

### Additional contract requirements

- Slack access tokens consist of several hyphen-separated segments. A real Slack access token of that form, such as `xoxp-41684372915-1320496754-45609968301-e708ba56e1517a99f6b5fb07349476ef`, must be detected by gitleaks' default rules.
- A placeholder-like string such as `xoxp-yourtokenhere` must not be flagged as a Slack token by gitleaks' default rules.
