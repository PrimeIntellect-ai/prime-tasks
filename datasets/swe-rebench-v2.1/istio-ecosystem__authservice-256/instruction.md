Possible regression: case-sensitive validation of token_type
[HIDDEN] This appears to be breaking our auth flows on the new version because ADFS returns the value as `bearer` (lowercase "b").

```
time="2024/05/10 14:48:12" level=debug msg="handling callback request" x-request-id="c772af90-0000-49a8-8a22-2b0c63d719f2" scope="authz" type="oidc" session-id="PEmFYiEPCYQImdc7OBLFhzOYgi7EmrzF3vysCSa9fLjXcknnYl8aimyK2HedRVJq"
time="2024/05/10 14:48:12" level=debug msg="getting authorization state" x-request-id="c772af90-0000-49a8-8a22-2b0c63d719f2" scope="session" type="memory" session-id="PEmFYiEPCYQImdc7OBLFhzOYgi7EmrzF3vysCSa9fLjXcknnYl8aimyK2HedRVJq"
time="2024/05/10 14:48:12" level=info msg="performing request to retrieve new tokens" x-request-id="c772af90-0000-49a8-8a22-2b0c63d719f2" scope="authz" type="oidc" session-id="PEmFYiEPCYQImdc7OBLFhzOYgi7EmrzF3vysCSa9fLjXcknnYl8aimyK2HedRVJq"
time="2024/05/10 14:48:12" level=info msg="token type is not Bearer in token response" x-request-id="c772af90-0000-49a8-8a22-2b0c63d719f2" scope="authz" type="oidc" session-id="PEmFYiEPCYQImdc7OBLFhzOYgi7EmrzF3vysCSa9fLjXcknnYl8aimyK2HedRVJq" token-type="bearer"
time="2024/05/10 14:48:12" level=debug msg="process result" x-request-id="c772af90-0000-49a8-8a22-2b0c63d719f2" scope="authz" type="oidc" session-id="PEmFYiEPCYQImdc7OBLFhzOYgi7EmrzF3vysCSa9fLjXcknnYl8aimyK2HedRVJq" allow=false status="InvalidArgument"
```

From [RFC-6749](https://datatracker.ietf.org/doc/html/rfc6749#section-5.1):
```
   token_type
         REQUIRED.  The type of the token issued as described in
         Section 7.1.  Value is case insensitive.
```

So it appears the old behavior of case-insensitive validation was correct.

### Additional contract requirements

- For both IDP new-token and refresh-token responses, accept `token_type` values case-insensitively, including lowercase `bearer`.
