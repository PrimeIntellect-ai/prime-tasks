source_profile is not working correctly.
- [v] I am using the latest release of AWS Vault
- [v] I have provided my `.aws/config` (redacted if necessary)
- [v] I have provided the debug output using `aws-vault --debug` (redacted if necessary)

It seems that the `source_profile` option is not working in 7.1.2-Homebrew version.
When I use with the `source_profile` with `dev`, the `get-caller-identity` always uses the `default` profile.

AWS CLI is working well, so I hope this feature is working same with the cli in the future.
Thanks.

```
> aws-vault exec test -- aws sts get-caller-identity
{
    "UserId": "ARxxxx:xxxx,
    "Account": "3701xxxx",
    "Arn": "arn:aws:sts::3701xxxx:assumed-role/xxxx"
}

> aws sts get-caller-identity --profile test
{
    "UserId": "ARxxxx:test",
    "Account": "3604xxxx",
    "Arn": "arn:aws:sts::3604xxxx:assumed-role/xxxx"
}

> vi ~/.aws/config
[profile test]
external_id=1d88xxxx
role_arn=arn:aws:iam::3604xxxx:role/xxxx
role_session_name=test
source_profile=dev
region=ap-northeast-2

[profile dev]
sso_session=common
sso_account_id=2160xxxx
sso_role_name=AdministratorAccess
region=ap-northeast-2
output=json

[default]
sso_session=common
sso_account_id=3701xxxx
sso_role_name=AdministratorAccess
region=ap-northeast-2
output=json

[sso-session common]
sso_start_url=https://xxxx.awsapps.com/start
sso_region=ap-northeast-2
sso_registration_scopes=sso:account:access
```

And here is the debug log.
```
aws-vault exec test --debug -- aws sts get-caller-identity
2023/03/20 09:16:32 aws-vault 7.1.2-Homebrew
2023/03/20 09:16:32 Using prompt driver: terminal
2023/03/20 09:16:32 Loading config file /Users/lamanus/.aws/config
2023/03/20 09:16:32 Parsing config file /Users/lamanus/.aws/config
2023/03/20 09:16:32 [keyring] Considering backends: [keychain]
2023/03/20 09:16:32 [keyring] Querying keychain for service="aws-vault", keychain="aws-vault.keychain"
2023/03/20 09:16:32 [keyring] Found 7 results
2023/03/20 09:16:32 profile test: using SSO role credentials
2023/03/20 09:16:32 Setting subprocess env: AWS_REGION=ap-northeast-2, AWS_DEFAULT_REGION=ap-northeast-2
2023/03/20 09:16:32 [keyring] Querying keychain for service="aws-vault", keychain="aws-vault.keychain"
2023/03/20 09:16:32 [keyring] Found 7 results
2023/03/20 09:16:32 [keyring] Querying keychain for service="aws-vault", keychain="aws-vault.keychain"
2023/03/20 09:16:32 [keyring] Found 7 results
2023/03/20 09:16:32 [keyring] Querying keychain for service="aws-vault", account="sso.GetRoleCredentials,dGVzdA,aHR0cHM6Ly9vcHNub3cuYXdzYXBwcy5jb20vc3RhcnQ,-62135596800", keychain="aws-vault.keychain"
2023/03/20 09:16:32 [keyring] No results found
2023/03/20 09:16:32 [keyring] Querying keychain for service="aws-vault", account="oidc:https://xxxx.awsapps.com/start", keychain="aws-vault.keychain"
2023/03/20 09:16:32 [keyring] Found item "aws-vault oidc token for https://xxxx.awsapps.com/start (expires 2023-03-20T17:12:17+09:00)"
2023/03/20 09:16:33 Got credentials ****************U7QJ for SSO role AdministratorAccess (account: 3701xxxx), expires in 11h59m58.598194s
2023/03/20 09:16:33 [keyring] Querying keychain for service="aws-vault", keychain="aws-vault.keychain"
2023/03/20 09:16:33 [keyring] Found 7 results
2023/03/20 09:16:33 [keyring] Querying keychain for service="aws-vault", keychain="aws-vault.keychain"
2023/03/20 09:16:33 [keyring] Found 7 results
2023/03/20 09:16:33 [keyring] Checking keychain status
2023/03/20 09:16:33 [keyring] Keychain status returned nil, keychain exists
2023/03/20 09:16:33 [keyring] Keychain item trusts keyring
2023/03/20 09:16:33 [keyring] Adding service="aws-vault", label="aws-vault session for test (expires 2023-03-20T21:16:32+09:00)", account="sso.GetRoleCredentials,dGVzdA,aHR0cHM6Ly9vcHNub3cuYXdzYXBwcy5jb20vc3RhcnQ,1679314592", trusted=true to osx keychain "aws-vault.keychain"
2023/03/20 09:16:33 Setting subprocess env: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
2023/03/20 09:16:33 Setting subprocess env: AWS_SESSION_TOKEN
2023/03/20 09:16:33 Setting subprocess env: AWS_CREDENTIAL_EXPIRATION
2023/03/20 09:16:33 Exec command aws sts get-caller-identity
2023/03/20 09:16:33 Found executable /opt/homebrew/bin/aws
{
    "UserId": "ARxxxx:xxxx,
    "Account": "3701xxxx",
    "Arn": "arn:aws:sts::3701xxxx:assumed-role/xxxx"
}
```

### Additional contract requirements

`NewTempCredentialsProvider` selects the credentials provider from the resolved profile. When session caching is disabled, the concrete provider type is returned:
- A profile with a `source_profile` is resolved through that source profile, and the source profile's settings take precedence over SSO settings inherited from it.
- A profile with a `role_arn` (AssumeRole flow) yields an `*AssumeRoleProvider`.
- A profile with stored credentials and an `mfa_serial` (GetSessionToken flow) yields an `*SessionTokenProvider`.
- A profile with a `web_identity_token_file` or `web_identity_token_process` (web-identity flow) yields an `*AssumeRoleWithWebIdentityProvider`.
- A profile with a `credential_process` (credential-process flow) yields an `*CredentialProcessProvider`.
- A profile with SSO settings yields an `*SSORoleCredentialsProvider`.
