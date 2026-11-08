2.8.0 breaks exiting scope handling
Last week's release introduced the following in the `getAccessToken()` function:

https://github.com/thephpleague/oauth2-client/pull/1030/files#diff-e8490e4bb8acb102745699d2bd7aa0a298d836c92d00d2ed57dd4c7ad8b24282

```
[HIDDEN]

if (is_array($options['scope'])) {
    $separator = $this->getScopeSeparator();
    $options['scope'] = implode($separator, $options['scope']);
}
```

This broke my existing integration because previously added scopes were lost and I got an API error: `ACCESS_TOKEN_SCOPE_INSUFFICIENT`.

To "fix" the issue, I had to add the scopes like this while refreshing the token:

```
$newAccessToken = $this->provider->getAccessToken('refresh_token', [
    'refresh_token' => $existingAccessToken->getRefreshToken(),
    'scope' => ['openid', 'email', 'profile', 'https://www.googleapis.com/auth/drive.file'],
]);
```

All the default (`'openid', 'email', 'profile'`) scopes, plus the one I already added while calling `getAuthorizationUrl()`. So to me, 2.8.0 is a breaking change that should have been mentioned.

### Additional contract requirements

When an access-token request omits `scope`, the provider must not add default scopes to the request parameters. When `scope` is supplied as an array, its values must be joined with the provider's configured scope separator before the request parameters are forwarded.
