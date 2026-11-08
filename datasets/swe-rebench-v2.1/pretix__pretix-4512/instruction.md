Reauth with Redirection Auth Backend does not work
### Problem and impact

Using OIDC Authentication using a pluggable authentication backend users will get thrown into a loop when they need to reauth, i.e. reauth page > OIDC authenticator > oidc callback > reauth page.

The logs suggest that the login was successful:

```test
INFO 2024-10-01 17:28:02,653 pretix.control.views.auth auth Backend login successful for user 7.
```

But the session seems to lack some information to get out of the reauth.

### Expected behaviour

The successful login after the reauth should lead to a working sessions.

### Steps to reproduce

1. Login using https://github.com/thegcat/pretix-oidc
2. Wait 3 hours and a bit
3. Reload a Pretix page
4. Click on the "Continue" button on the reauth page
5. Some OIDC dance
6. Be back on the reauth page.

I have followed the different URLs/redirection in my browser. The order is:
1. GET https://pretix/control/reauth/
2. GET https://oidc-provider/authorize
3. GET https://pretix/oidc/callback/ (from I can gather the "Backend login successful" happens here)
4. GET https://pretix/control/
5. GET https://pretix/control/reauth/

### Screenshots

_No response_

### Link

_No response_

### Browser (software, desktop or mobile?) and version

_No response_

### Operating system, dependency versions

_No response_

### Version

2024.9.0
