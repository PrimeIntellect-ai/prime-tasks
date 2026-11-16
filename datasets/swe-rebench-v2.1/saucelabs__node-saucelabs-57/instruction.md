Full region name responds with DNS error
**Short summary of what the user sees:**
If a user tries to to use a region name that is not the "short" version it will fail

**Exact steps to reproduce the problem:**
1. Download latest version of saucelabs module (at time of bug report 2.1.8)
2. Try running any command via CLI or as module with a region that is not eu or us.
Example:
sl listJobs $SAUCE_USERNAME --limit 5 --region us-central-1

*Isolation: What must be true for it to happen? When does it not happen?*
Seems to only happen if you use the full region name.

**Links to Relevant Test Archives or Logs:**
```
➜  ~ sl listJobs $SAUCE_USERNAME --limit 5 --region us-central-1
{ Error: getaddrinfo ENOTFOUND us-west-1.saucelabs.com us-west-1.saucelabs.com:443
    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:57:26)
  errno: 'ENOTFOUND',
  code: 'ENOTFOUND',
  syscall: 'getaddrinfo',
  hostname: 'us-west-1.saucelabs.com',
  host: 'us-west-1.saucelabs.com',
  port: 443 }
➜  ~ sl listJobs $SAUCE_USERNAME --limit 5 --region us-west-1
{ Error: getaddrinfo ENOTFOUND us-west-1.saucelabs.com us-west-1.saucelabs.com:443
    at GetAddrInfoReqWrap.onlookup [as oncomplete] (dns.js:57:26)
  errno: 'ENOTFOUND',
  code: 'ENOTFOUND',
  syscall: 'getaddrinfo',
  hostname: 'us-west-1.saucelabs.com',
  host: 'us-west-1.saucelabs.com',
  port: 443 }
```

**What attempts were made to find the root cause so far?**
This might be due to how we use the REGION_MAPPINGS and how we determine the correct DC.
https://github.com/saucelabs/node-saucelabs/blob/656b8e770c44f720dfe0b4b47b7bdf2d5d5df9bc/src/constants.js#L61
https://github.com/saucelabs/node-saucelabs/blob/656b8e770c44f720dfe0b4b47b7bdf2d5d5df9bc/src/utils.js#L43-L51

us-west-1.saucelabs.com doesn't work (not sure if intended) but eu-central-1.saucelabs.com does.
We could have us-west-1 default to saucelabs.com or app.saucelabs.com and have eu-central-1 just append the name.

### Additional contract requirements

- For `getSauceEndpoint('saucelabs.com', 'us-west-1', false)`, the result must be `https://saucelabs.com`.
- For `getSauceEndpoint('saucelabs.com', 'I_DONT_EXIST', false)`, the result must be `https://saucelabs.com`.
