Authelia doesn't accept empty base_dn for LDAP backend
### Version


v4.38.16

### Deployment Method


Docker

### Reverse Proxy


NGINX

### Reverse Proxy Version


1.26

### Description


When using LDAP as authentication backend, Authelia doesn't allow to have an empty Base DN field (which means I'd like to search from LDAP root).

LDAP allow to provide an empty Base DN:

```
ldapsearch -b '' -D '******' -H ldap://a.b.c.d -x -w ******  '(&(mail=nicolas@domain.tld)(objectClass=people))' dn

# nicolas, people, domain.tld
dn: uid=nicolas,ou=people,dc=domain,dc=tld
```

However, Authelia doesn't accept empty Base DN as in the above example and fails to start.

This is a problem for me because I have a multi-domains LDAP, and since empty Base DN is not allowed, I am forced to set it up for a specific domain (eg. **dc=domain,dc=tld**). This forces me to have 1 authelia instance per domain, this is both non scalable and resources consuming.

Thanks !


### Reproduction


Start authelia with:

```ldap
authentication_backend:
  ldap:
    base_dn: ''
```

### Expectations


Empty Base DN should be accepted

### Configuration (Authelia)


```yaml
---
###############################################################
#                   Authelia configuration                    #
###############################################################

# docker run authelia/authelia:4.38 authelia crypto rand --length 64 --charset alphanumeric
identity_validation:
  reset_password:
    jwt_secret: '******'

access_control:
  default_policy: 'deny'
  rules:
    - domain:
        - "sub.domain.tld"
      policy: one_factor

session:
  secret: '******'
  name: 'authelia_session'
  same_site: 'lax'
  inactivity: '5m'
  expiration: '1h'
  remember_me: '1M'
  cookies:
    - domain: 'domain.tld'
      authelia_url: 'https://auth.domain.tld'
      default_redirection_url: 'https://www.domain.tld'
      name: 'authelia_session'
      same_site: 'lax'
      inactivity: '5m'
      expiration: '1h'
      remember_me: '1d'

storage:
  encryption_key: '******'
  local:
    path: '/config/db.sqlite3'

server:
  address: 'tcp://:9091'
  endpoints:
    authz:
      auth-request:
        implementation: 'AuthRequest'

log:
  level: 'info'

ntp:
  address: 'udp://ntp.domain.tld:123'
  version: 3
  max_desync: '3s'
  disable_startup_check: false
  disable_failure: false

authentication_backend:
  password_reset:
    disable: true
  ldap:
    address: 'ldap://ldap.domain.tld'
    implementation: 'custom'
    timeout: '5s'
    start_tls: true
    base_dn: 'dc=domain,dc=tld'
    additional_users_dn: 'ou=people'
    users_filter: '(&({username_attribute}={input})(objectClass=people))'
    groups_filter: '(&(member={dn})(objectClass=groupOfNames))'
    group_search_mode: 'filter'
    permit_referrals: false
    permit_unauthenticated_bind: false
    user: '******'
    password: '******'
    attributes:
      distinguished_name: 'dn'
      username: 'sn'
      display_name: 'cn'
      mail: 'mail'
      member_of: 'memberOf'
      group_name: 'cn'

notifier:
  disable_startup_check: false
  smtp:
    address: 'smtp://smtp.domain.tld:25'
    timeout: '5s'
    sender: "Authelia <admin@domain.tld>"
    identifier: 'authelia'
    subject: "[Authelia] {title}"
    startup_check_address: 'admin@domain.tld'
    disable_require_tls: false
    disable_starttls: false
    disable_html_emails: false
```


### Build Information


```shell
Last Tag: v4.38.16
State: tagged clean
Branch: v4.38.16
Commit: 83023d051500e5073acb468b67b90a84ce958ea8
Build Number: 33895
Build OS: linux
Build Arch: amd64
Build Compiler: gc
Build Date: Sun, 06 Oct 2024 22:18:20 +1100
Extra:

Go:
    Version: go1.23.1
    Module Path: github.com/authelia/authelia/v4
    Executable Path: github.com/authelia/authelia/v4/cmd/authelia
```


### Logs (Authelia)


```shell
time="2024-10-21T05:27:01Z" level=error msg="Configuration: authentication_backend: ldap: option 'base_dn' is required"
time="2024-10-21T05:27:01Z" level=fatal msg="Can't continue due to the errors loading the configuration" stack="github.com/authelia/authelia/v4/internal/commands/context.go:327 (*CmdCtx).ConfigValidateLogRunE\ngithub.com/authelia/authelia/v4/internal/commands/context.go:186 NewRootCmd.(*CmdCtx).ChainRunE.func1\ngithub.com/spf13/cobra@v1.8.1/command.go:970                     (*Command).execute\ngithub.com/spf13/cobra@v1.8.1/command.go:1117                    (*Command).ExecuteC\ngithub.com/spf13/cobra@v1.8.1/command.go:1041                    (*Command).Execute\ngithub.com/authelia/authelia/v4/cmd/authelia/main.go:10          main\ninternal/runtime/atomic/types.go:194                             (*Uint32).Load\nruntime/asm_amd64.s:1700                                         goexit"
```


### Logs (Proxy / Application)


_No response_

### Documentation


_No response_

### Pre-Submission Checklist


- [X] I agree to follow the [Code of Conduct](http://www.authelia.com/code-of-conduct)

- [X] This is a bug report and not a support request

- [X] I have read the security policy and this bug report is not a security issue or security related issue

- [X] I have either included the complete configuration file or I am sure it's unrelated to the configuration

- [X] I have either included the complete debug / trace logs or the output of the build-info command if the logs are not relevant

- [X] I have provided all of the required information in full with the only alteration being reasonable sanitization in accordance with the [Troubleshooting Sanitization](https://www.authelia.com/r/sanitize) reference guide

- [X] I have checked for related proxy or application logs and included them if available

- [X] I have checked for related issues and checked the documentation
