Synology docker - invalid memory address or nil pointer derefernce - PGID not correct
### Version


v4.38.9

### Deployment Method


Docker

### Reverse Proxy


SWAG

### Reverse Proxy Version


_No response_

### Description


When I try to make the authelia docker run I get the following log:

```
time="2024-07-24T14:26:27Z" level=debug msg="Loaded Configuration Sources" files="[/config/configuration.yml]" filters="[]"
time="2024-07-24T14:26:27Z" level=debug msg="Logging Initialized" fields.level=debug file=/config/authelia.log format=text keep_stdout=true
time="2024-07-24T14:26:27Z" level=debug msg="Process user information" gid=1040 uid=1040
time="2024-07-24T14:26:27Z" level=warning msg="Configuration: configuration key 'session.remember_me_duration' is deprecated in 4.38.0 and has been replaced by 'session.remember_me': you are not required to make any changes as this has been automatically mapped for you, but to stop this warning being logged you will need to adjust your configuration, and this configuration key and auto-mapping is likely to be removed in 5.0.0"
time="2024-07-24T14:26:27Z" level=warning msg="Configuration: configuration keys 'storage.mysql.host' and 'storage.mysql.port' are deprecated in 4.38.0 and has been replaced by 'storage.mysql.address' in the format of '[tcp://]<hostname>[:<port>]': you are not required to make any changes as this has been automatically mapped for you to the value 'tcp://192.168.0.11:3306', but to stop this warning being logged you will need to adjust your configuration, and this configuration key and auto-mapping is likely to be removed in 5.0.0"
time="2024-07-24T14:26:27Z" level=warning msg="Configuration: session: option 'domain' is deprecated in v4.38.0 and has been replaced by a multi-domain configuration: this has automatically been mapped for you but you will need to adjust your configuration to remove this message and receive the latest messages"
time="2024-07-24T14:26:27Z" level=info msg="Authelia v4.38.9 is starting"
time="2024-07-24T14:26:27Z" level=info msg="Log severity set to debug"
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x0 pc=0x556c4c8a60b5]

goroutine 1 [running]:
github.com/authelia/authelia/v4/internal/storage.dsnPostgreSQL(0xc000624540, 0xc000fc07b0)
	github.com/authelia/authelia/v4/internal/storage/sql_provider_backend_postgres.go:156 +0x35
github.com/authelia/authelia/v4/internal/storage.NewPostgreSQLProvider(0xc000570008, 0xc00005e740?)
	github.com/authelia/authelia/v4/internal/storage/sql_provider_backend_postgres.go:25 +0x34
github.com/authelia/authelia/v4/internal/commands.getStorageProvider(0x0?)
	github.com/authelia/authelia/v4/internal/commands/helpers.go:18 +0x170
github.com/authelia/authelia/v4/internal/commands.(*CmdCtx).LoadProviders(0xc000b9a8f0)
	github.com/authelia/authelia/v4/internal/commands/context.go:144 +0xc5
github.com/authelia/authelia/v4/internal/commands.(*CmdCtx).RootRunE(0xc000b9a8f0, 0xc0000fdbb0?, {0x0?, 0x0?, 0x0?})
	github.com/authelia/authelia/v4/internal/commands/root.go:72 +0x233
github.com/spf13/cobra.(*Command).execute(0xc000574008, {0xc000040070, 0x0, 0x0})
	github.com/spf13/cobra@v1.8.1/command.go:985 +0xaca
github.com/spf13/cobra.(*Command).ExecuteC(0xc000574008)
	github.com/spf13/cobra@v1.8.1/command.go:1117 +0x3ff
github.com/spf13/cobra.(*Command).Execute(0xc0000061c0?)
	github.com/spf13/cobra@v1.8.1/command.go:1041 +0x13
main.main()
	github.com/authelia/authelia/v4/cmd/authelia/main.go:10 +0x18

```
What is irritating me:

- Line: time="2024-07-24T14:26:27Z" level=debug msg="Process user information" gid=1040 uid=1040
Why is the gid=1040 although the env-parameter PGID=100 (and PUID=1040)??
- Lind: panic: runtime error: invalid memory address or nil pointer dereference
Does the error actually has something in common with the wrong GID?? (after reading on the internet it seems that this error has something to do with permissions)


Env-variables:
AUTHELIA_IDENTITY_VALIDATION_RESET_PASSWORD_JWT_SECRET_FILE	/secrets/authelia_jwt_secret
AUTHELIA_SESSION_SECRET_FILE	/secrets/authelia_session_secret
AUTHELIA_STORAGE_ENCRYPTION_KEY_FILE	/secrets/authelia_storage_encryption_key
AUTHELIA_STORAGE_POSTGRES_PASSWORD_FILE	/secrets/authelia_storage_encryption_key
PATH	/app:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
PGID	100
PUID	1040


Thanks for your support

### Reproduction


every restart of docker

### Expectations


Correct starting Authelia installation

### Configuration (Authelia)


```yaml
###############################################################
#                   Authelia configuration                    #
###############################################################

# https://www.authelia.com/configuration/miscellaneous/introduction/#default_redirection_url

## The theme to display: light, dark, grey, auto.
theme: 'light'

## Set the default 2FA method for new users and for when a user has a preferred method configured that has been
## disabled. This setting must be a method that is enabled.
## Options are totp, webauthn, mobile_push.
default_2fa_method: 'totp'

server:
  address: 'tcp://:9091/'


# https://www.authelia.com/configuration/miscellaneous/logging/
log:
  level: 'debug'
  format: 'text'
  file_path: '/config/authelia.log'
  keep_stdout: true

# https://www.authelia.com/configuration/second-factor/time-based-one-time-password/
totp:
  issuer: 'xxx.yyy'
  period: 30
  skew: 1

# https://www.authelia.com/reference/guides/passwords/
authentication_backend:
  ldap:
    implementation: 'custom'
    address: 'ldap://xxx.xxx.xxx.xxx'
    start_tls: false
    base_dn: 'dc=xxx,dc=yyy' # enter the values from the LDAP config
    additional_users_dn: 'cn=users'
    additional_groups_dn: 'cn=groups'
    groups_filter: '(&(uniquemember={dn})(objectclass=groupOfUniqueNames))'
    users_filter: '(&({username_attribute}={input})(objectClass=person))'
    user: 'uid=admin,cn=users,dc=xxx,dc=yyy' # your LDAP parameters
    password: '*******' # LDAP Admin password

# https://www.authelia.com/overview/authorization/access-control/
access_control:
  default_policy: 'deny'
  rules:
    ## Rules applied to user 'admin'
    - domain: '*.xxx.yyy'
      subject: 'user:admin'
      policy: 'two_factor'

# https://www.authelia.com/configuration/session/introduction/
session:
  name: 'authelia_session'
  expiration: '1h'
  inactivity: '5m'
  remember_me_duration: '1M'
  domain: 'xxx.yyy' # Should match whatever your root protected domain is

  redis:
    host: 'xxx.xxx.xxx.xxx' # something like 10.20.30.35
    port: 6380 # port for REDIS docker contianer
    database_index: 1 # change this if you already use REDIS for something

# https://www.authelia.com/configuration/security/regulation/
regulation:
  max_retries: 3
  find_time: 300
  ban_time: 60000

# https://www.authelia.com/configuration/storage/introduction/
storage:
  mysql:
    host: 'xxx.xxx.xxx'
    port: '3306' # mysql docker container port
    database: 'authelia' # change to the name you have configured
    username: 'authelia' # change to the user you have configured
    password: '********' # change to the password you have configured

# https://www.authelia.com/configuration/notifications/introduction/
notifier:
  disable_startup_check: false
  # For testing purposes, notifications can be sent in a file. Be sure to map the volume in docker-compose.
  filesystem:
    filename: '/config/notifications.txt'
```


### Build Information


```shell
standard docker image
```


### Logs (Authelia)


```shell
see above
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

### Additional contract requirements

When configuration settings select more than one storage backend (local, MySQL, or PostgreSQL), validation must reject the configuration before startup can reach a nil-pointer panic.
