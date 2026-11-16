Allow slack url to be in a token
**Is your feature request related to a problem? Please describe.**

In our prior workflow, we put the slack URL in an environment variable so folks are less likely to abuse it (see https://github.com/intuit/semantic-release-slack#usage). It would be nice to have a similar flow in auto so we don't have to check in our URLs for the public to see.

**Describe the solution you'd like**

Allowing the slack step to look for `SLACK_WEBHOOK_URL` or some paradigm such that I don't have to set the URL in the repo

**Describe alternatives you've considered**

N/A
