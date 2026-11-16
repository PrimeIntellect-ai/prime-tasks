Segmentation violation
### Version


v4.38.16

### Deployment Method


Docker

### Reverse Proxy


Traefik

### Reverse Proxy Version


2.10.7

### Description


The docker container crashes on startup.

### Reproduction


Simply run the container with the config below and it will crash immediately.

### Expectations


_No response_

### Configuration (Authelia)


```yaml
---
###############################################################
#                   Authelia configuration                    #
###############################################################

# This secret can also be set using the env variables AUTHELIA_JWT_SECRET_FILE
# generate with 'docker run authelia/authelia:latest authelia crypto rand --length 128 --charset alphanumeric'

identity_validation:
  reset_password:
    jwt_secret: xxxx
default_redirection_url: https://auth.domain.com

log:
  level: debug

totp:
  issuer: auth.domain.com

# register to duo to use this
# duo_api:
#  hostname: api-123456789.example.com
#  integration_key: ABCDEF
#  # This secret can also be set using the env variables AUTHELIA_DUO_API_SECRET_KEY_FILE
#  secret_key: 1234567890abcdefghifjkl

authentication_backend:
  file:
    path: /config/users_database.yml

access_control:
  default_policy: deny
  rules:
    # Rules applied to everyone # bypass, one_factor, two_factor
    - domain: unsecure.whoami.example.com
      policy: bypass
    - domain: domain.com
      policy: one_factor
    - domain: "*.domain.com"
      policy: bypass

session:
  name: authelia_session
  secret: xxxx
  expiration: 1h
  inactivity: 5m
  remember_me: 1M
  cookies:
    - domain: domain.com
      authelia_url: https://auth.domain.com

regulation:
  max_retries: 3
  find_time: 120  # how often max retires are counted
  ban_time: 300

storage:
# generate with 'docker run authelia/authelia:latest authelia crypto rand --length 128 --charset alphanumeric'
  encryption_key: xxxx
  local:
    path: /config/db.sqlite3

notifier:
  smtp:
    username: xxxx
    # This secret can also be set using the env variables AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE
    password: xxx
    address: xxxx
    sender: xxx
  # For testing purpose, notifications can be sent in a file.
  # filesystem:
  #   filename: /config/notification.txt

identity_providers:
  oidc:
    ## The other portions of the mandatory OpenID Connect 1.0 configuration go here.
    ## See: https://www.authelia.com/c/oidc
    ##### generate with 'docker run authelia/authelia:latest authelia crypto rand --length 128 --charset alphanumeric'
    hmac_secret: xxxx
    # INFO: n and e values are not from an actual key
    jwks:
      - use: sig
        kty: RSA
        kid: default
        alg: RS256
        n: 234823498234982398472342387623498674726394823748234
        e: 65537
    clients:
    - client_id: portainer
      client_name: Portainer
      # generate with 'docker run authelia/authelia:latest authelia crypto hash generate pbkdf2 --variant sha512 --random --random.length 72 --random.charset rfc3986'
      client_secret: 'xxxx'.
      public: false
      authorization_policy: two_factor
      redirect_uris:
        - https://portainer.domain.com
      scopes:
        - openid
        - profile
        - groups
        - email
      userinfo_signed_response_alg: none
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
time="2024-10-13T01:00:10+02:00" level=debug msg="Loaded Configuration Sources" files="[/config/configuration.yml]" filters="[]"
time="2024-10-13T01:00:10+02:00" level=debug msg="Logging Initialized" fields.level=debug file= format= keep_stdout=false
time="2024-10-13T01:00:10+02:00" level=debug msg="Process user information" gid=1000 uid=1000
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=0x5623697789ff]

goroutine 1 [running]:
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuerPrivateKeysUseAlg(0x0, 0x0?, 0xc000552c40, 0xc000bbc0f0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:232 +0x33f
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuerJSONWebKeys(0xc000552c40, 0xc000bbc0f0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:211 +0xdde
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuer(0xc000552c40, 0xc000bbc0f0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:130 +0x35f
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDC(0xc000ce8180, 0xc000552c40, 0xc000bbc0f0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:31 +0xe5
github.com/authelia/authelia/v4/internal/configuration/validator.ValidateIdentityProviders(...)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:21
github.com/authelia/authelia/v4/internal/configuration/validator.ValidateConfiguration(0xc000b48508, 0xc000bbc0f0, {0xc0005e5c18, 0x1, 0x56236a6a1368?})
        github.com/authelia/authelia/v4/internal/configuration/validator/configuration.go:66 +0x5ad
github.com/authelia/authelia/v4/internal/commands.(*CmdCtx).HelperConfigValidateRunE(0xc000524270, 0xc000b54008?, {0x562369c675c9?, 0x7?, 0x56236902b812?})
        github.com/authelia/authelia/v4/internal/commands/context.go:238 +0x8c
github.com/authelia/authelia/v4/internal/commands.NewRootCmd.(*CmdCtx).ChainRunE.func1(0xc000b54008, {0x56236b228a00, 0x0, 0x0})
        github.com/authelia/authelia/v4/internal/commands/context.go:186 +0x79
github.com/spf13/cobra.(*Command).execute(0xc000b54008, {0xc000040090, 0x0, 0x0})
        github.com/spf13/cobra@v1.8.1/command.go:970 +0xa24
github.com/spf13/cobra.(*Command).ExecuteC(0xc000b54008)
        github.com/spf13/cobra@v1.8.1/command.go:1117 +0x3ff
github.com/spf13/cobra.(*Command).Execute(0xc0000061c0?)
        github.com/spf13/cobra@v1.8.1/command.go:1041 +0x13
main.main()
        github.com/authelia/authelia/v4/cmd/authelia/main.go:10 +0x18
time="2024-10-13T01:00:10+02:00" level=debug msg="Loaded Configuration Sources" files="[/config/configuration.yml]" filters="[]"
time="2024-10-13T01:00:10+02:00" level=debug msg="Logging Initialized" fields.level=debug file= format= keep_stdout=false
time="2024-10-13T01:00:10+02:00" level=debug msg="Process user information" gid=1000 uid=1000
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=0x55fa0e6369ff]

goroutine 1 [running]:
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuerPrivateKeysUseAlg(0x0, 0x0?, 0xc000105dc0, 0xc000639d10)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:232 +0x33f
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuerJSONWebKeys(0xc000105dc0, 0xc000639d10)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:211 +0xdde
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuer(0xc000105dc0, 0xc000639d10)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:130 +0x35f
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDC(0xc00075dda0, 0xc000105dc0, 0xc000639d10)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:31 +0xe5
github.com/authelia/authelia/v4/internal/configuration/validator.ValidateIdentityProviders(...)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:21
github.com/authelia/authelia/v4/internal/configuration/validator.ValidateConfiguration(0xc00031cf08, 0xc000639d10, {0xc00001dc18, 0x1, 0x55fa0f55f368?})
        github.com/authelia/authelia/v4/internal/configuration/validator/configuration.go:66 +0x5ad
github.com/authelia/authelia/v4/internal/commands.(*CmdCtx).HelperConfigValidateRunE(0xc000658410, 0xc00062a008?, {0x55fa0eb255c9?, 0x7?, 0x55fa0dee9812?})
        github.com/authelia/authelia/v4/internal/commands/context.go:238 +0x8c
github.com/authelia/authelia/v4/internal/commands.NewRootCmd.(*CmdCtx).ChainRunE.func1(0xc00062a008, {0x55fa100e6a00, 0x0, 0x0})
        github.com/authelia/authelia/v4/internal/commands/context.go:186 +0x79
github.com/spf13/cobra.(*Command).execute(0xc00062a008, {0xc000164040, 0x0, 0x0})
        github.com/spf13/cobra@v1.8.1/command.go:970 +0xa24
github.com/spf13/cobra.(*Command).ExecuteC(0xc00062a008)
        github.com/spf13/cobra@v1.8.1/command.go:1117 +0x3ff
github.com/spf13/cobra.(*Command).Execute(0xc0000061c0?)
        github.com/spf13/cobra@v1.8.1/command.go:1041 +0x13
main.main()
        github.com/authelia/authelia/v4/cmd/authelia/main.go:10 +0x18
time="2024-10-13T01:00:11+02:00" level=debug msg="Loaded Configuration Sources" files="[/config/configuration.yml]" filters="[]"
time="2024-10-13T01:00:11+02:00" level=debug msg="Logging Initialized" fields.level=debug file= format= keep_stdout=false
time="2024-10-13T01:00:11+02:00" level=debug msg="Process user information" gid=1000 uid=1000
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=0x5621dc8d39ff]

goroutine 1 [running]:
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuerPrivateKeysUseAlg(0x0, 0x0?, 0xc000331500, 0xc0003eecf0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:232 +0x33f
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuerJSONWebKeys(0xc000331500, 0xc0003eecf0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:211 +0xdde
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuer(0xc000331500, 0xc0003eecf0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:130 +0x35f
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDC(0xc0005fed80, 0xc000331500, 0xc0003eecf0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:31 +0xe5
github.com/authelia/authelia/v4/internal/configuration/validator.ValidateIdentityProviders(...)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:21
github.com/authelia/authelia/v4/internal/configuration/validator.ValidateConfiguration(0xc000320f08, 0xc0003eecf0, {0xc0006edc18, 0x1, 0x5621dd7fc368?})
        github.com/authelia/authelia/v4/internal/configuration/validator/configuration.go:66 +0x5ad
github.com/authelia/authelia/v4/internal/commands.(*CmdCtx).HelperConfigValidateRunE(0xc0004a1040, 0xc0006a8608?, {0x5621dcdc25c9?, 0x7?, 0x5621dc186812?})
        github.com/authelia/authelia/v4/internal/commands/context.go:238 +0x8c
github.com/authelia/authelia/v4/internal/commands.NewRootCmd.(*CmdCtx).ChainRunE.func1(0xc0006a8608, {0x5621de383a00, 0x0, 0x0})
        github.com/authelia/authelia/v4/internal/commands/context.go:186 +0x79
github.com/spf13/cobra.(*Command).execute(0xc0006a8608, {0xc000040090, 0x0, 0x0})
        github.com/spf13/cobra@v1.8.1/command.go:970 +0xa24
github.com/spf13/cobra.(*Command).ExecuteC(0xc0006a8608)
        github.com/spf13/cobra@v1.8.1/command.go:1117 +0x3ff
github.com/spf13/cobra.(*Command).Execute(0xc0000061c0?)
        github.com/spf13/cobra@v1.8.1/command.go:1041 +0x13
main.main()
        github.com/authelia/authelia/v4/cmd/authelia/main.go:10 +0x18
time="2024-10-13T01:00:11+02:00" level=debug msg="Loaded Configuration Sources" files="[/config/configuration.yml]" filters="[]"
time="2024-10-13T01:00:11+02:00" level=debug msg="Logging Initialized" fields.level=debug file= format= keep_stdout=false
time="2024-10-13T01:00:11+02:00" level=debug msg="Process user information" gid=1000 uid=1000
panic: runtime error: invalid memory address or nil pointer dereference
[signal SIGSEGV: segmentation violation code=0x1 addr=0x18 pc=0x556f6a2819ff]

goroutine 1 [running]:
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuerPrivateKeysUseAlg(0x0, 0x0?, 0xc00058a8c0, 0xc0009560f0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:232 +0x33f
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuerJSONWebKeys(0xc00058a8c0, 0xc0009560f0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:211 +0xdde
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDCIssuer(0xc00058a8c0, 0xc0009560f0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:130 +0x35f
github.com/authelia/authelia/v4/internal/configuration/validator.validateOIDC(0xc000c90180, 0xc00058a8c0, 0xc0009560f0)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:31 +0xe5
github.com/authelia/authelia/v4/internal/configuration/validator.ValidateIdentityProviders(...)
        github.com/authelia/authelia/v4/internal/configuration/validator/identity_providers.go:21
github.com/authelia/authelia/v4/internal/configuration/validator.ValidateConfiguration(0xc0008de508, 0xc0009560f0, {0xc000551c18, 0x1, 0x556f6b1aa368?})
        github.com/authelia/authelia/v4/internal/configuration/validator/configuration.go:66 +0x5ad
github.com/authelia/authelia/v4/internal/commands.(*CmdCtx).HelperConfigValidateRunE(0xc0005b2340, 0xc0008ea008?, {0x556f6a7705c9?, 0x7?, 0x556f69b34812?})
        github.com/authelia/authelia/v4/internal/commands/context.go:238 +0x8c
github.com/authelia/authelia/v4/internal/commands.NewRootCmd.(*CmdCtx).ChainRunE.func1(0xc0008ea008, {0x556f6bd31a00, 0x0, 0x0})
        github.com/authelia/authelia/v4/internal/commands/context.go:186 +0x79
github.com/spf13/cobra.(*Command).execute(0xc0008ea008, {0xc000040090, 0x0, 0x0})
        github.com/spf13/cobra@v1.8.1/command.go:970 +0xa24
github.com/spf13/cobra.(*Command).ExecuteC(0xc0008ea008)
        github.com/spf13/cobra@v1.8.1/command.go:1117 +0x3ff
github.com/spf13/cobra.(*Command).Execute(0xc0000061c0?)
        github.com/spf13/cobra@v1.8.1/command.go:1041 +0x13
main.main()
        github.com/authelia/authelia/v4/cmd/authelia/main.go:10 +0x18
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

When an OIDC issuer JWK has no usable key material, configuration validation must report an error instead of accepting the key. It must do so without panicking.
