Stateless JWT access token introspection stopped working after v4.39.2 changes
### Version


v4.39.2

### Deployment Method


Bare-metal

### Reverse Proxy

None

### Reverse Proxy Version

N/A

### Description


With the exact same configuration as in issue #9382 (I simply changed the deployed version from v4.39.1 to v4.39.2) the access token is no longer a JWT.

### Reproduction


- Use the configuration in issue #9382
- Perform a PKCE exchange

### Expectations


I expected a JWT access token but got `authelia_at_00GpPfhNvbj9-0aNUDbU46Pt31T29Zuo9IfMLiamOag.fRAeFx5JY-FN0kq1J7QQx7LT9M4heyri7P-2EqDb-kk`

### Configuration (Authelia)


```yaml
See issue #9382
```

### Build Information


```shell
Last Tag: v4.39.2
State: tagged clean
Branch: v4.39.2
Commit: 1266ffea0a71ce495c3906375b1f1fd1a475bef7
Build Number: 43938
Build OS: linux
Build Arch: amd64
Build Compiler: gc
Build Date: Sat, 10 May 2025 15:15:27 +1000
Extra:

Go:
    Version: go1.24.3 X:nosynchashtriemap
    Module Path: github.com/authelia/authelia/v4
    Executable Path: github.com/authelia/authelia/v4/cmd/authelia
```

### Logs (Authelia)


```shell
May 11 03:01:34 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:34Z" level=info msg="Log severity set to debug"
May 11 03:01:34 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:34Z" level=debug msg="Registering OpenID Connect 1.0 client with client id 'XXX' and policy 'XXX'"
May 11 03:01:34 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:34Z" level=info msg="Storage schema is being checked for updates"
May 11 03:01:34 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:34Z" level=info msg="Storage schema is already up to date"
May 11 03:01:35 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:35Z" level=debug msg="LDAP Supported OIDs. Control Types: none. Extensions: 1.3.6.1.4.1.4203.1.11.1"
May 11 03:01:35 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:35Z" level=debug msg="notification provider: startup check skipped as it is disabled"
May 11 03:01:35 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:35Z" level=debug msg="webauthn-metadata provider: startup check skipped as it is disabled"
May 11 03:01:35 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:35Z" level=info msg="Listening for non-TLS connections on '[::]:8080' path '/'" server=main service=server
May 11 03:01:35 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:35Z" level=info msg="Listening for non-TLS connections on '127.0.0.1:9959' path '/metrics'" server=metrics service=server
May 11 03:01:35 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:35Z" level=info msg="Startup complete"
May 11 03:01:45 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:45Z" level=debug msg="Authorization Request with id '9b575b04-5b3c-4338-ac49-d3ebb706d2ed' on client with id 'idetrust-console-dev' is being processed" method=GET path=/api/oidc/authorization remote_ip=XXX
May 11 03:01:56 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:56Z" level=debug msg="Mark 1FA authentication attempt made by user 'felix'" method=POST path=/api/firstfactor remote_ip=XXX
May 11 03:01:56 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:56Z" level=debug msg="Successful 1FA authentication attempt made by user 'felix'" method=POST path=/api/firstfactor remote_ip=XXX
May 11 03:01:57 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:57Z" level=debug msg="Authorization Request with id 'd1ab5461-d5a2-4c24-ae3b-43000a3555c6' on client with id 'idetrust-console-dev' is being processed" method=GET path=/api/oidc/authorization remote_ip=XXX
May 11 03:01:57 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:57Z" level=debug msg="Authorization Request with id 'd1ab5461-d5a2-4c24-ae3b-43000a3555c6' on client with id 'XXX' is not being redirected for reauthentication" authenticated_at="2025-05-11 03:01:56 +0000 UTC" method=GET path=/api/oidc/authorization prompt= remote_ip=XXX requested_at="2025-05-11 03:01:45.119962698 +0000 UTC"
May 11 03:01:57 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:57Z" level=debug msg="Authorization Request with id 'd1ab5461-d5a2-4c24-ae3b-43000a3555c6' on client with id 'XXX' was successfully processed, proceeding to build Authorization Response" method=GET path=/api/oidc/authorization remote_ip=XXX
May 11 03:01:58 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:58Z" level=debug msg="Access Request with id 'd1ab5461-d5a2-4c24-ae3b-43000a3555c6' on client with id 'XXX' is being processed" method=POST path=/api/oidc/token remote_ip=XXX
May 11 03:01:58 ip-10-1-2-233.eu-central-1.compute.internal authelia[2564]: time="2025-05-11T03:01:58Z" level=debug msg="Access Request with id 'd1ab5461-d5a2-4c24-ae3b-43000a3555c6' on client with id 'XXX' has successfully been processed" method=POST path=/api/oidc/token remote_ip=XXX
```

### Logs (Proxy / Application)


```shell
N/A
```

### Documentation


_No response_

### Generative AI


No

### Pre-Submission Checklist


- [x] I agree to follow the [Code of Conduct](http://www.authelia.com/code-of-conduct)

- [x] This is a bug report and not a support request

- [x] I have read the security policy and this bug report is not a security issue or security related issue

- [x] I have either included the complete configuration file or I am sure it's unrelated to the configuration

- [x] I have either included the complete debug / trace logs or the output of the build-info command if the logs are not relevant

- [x] I have provided all of the required information in full with the only alteration being reasonable sanitization in accordance with the [Troubleshooting Sanitization](https://www.authelia.com/r/sanitize) reference guide

- [x] I have checked for related proxy or application logs and included them if available

- [x] I have checked for related issues and checked the documentation

### Additional contract requirements

- When a client is configured with a valid JWT signing algorithm for its access tokens (for example, `access_token_signed_response_alg` set to `RS256`), the access tokens issued for that client must be JWTs rather than opaque tokens.
