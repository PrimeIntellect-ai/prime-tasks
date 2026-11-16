OIDC: redirect_uris for owncloud iOS app
## Feature Request
<!--
1. IMPORTANT: Do not report security vulnerabilities via GitHub issues. Please click 'choose a different type' and see
the dedicated report a security vulnerability link.
2. Remember to customize the title above.
3. Replace the below sections (not this section) starting with <!- - and ending with - -> with relevant information,
making sure to remove the <!- - and - ->.
4. Sections that start with _N/A_ are optional, but if you populate them with values please remove the _N/A_.
-->

### Description
ownCloud iOS app expects client `redirect_uris` to be `oc://ios.owncloud.com` according to the [doc](https://doc.owncloud.com/server/next/admin_manual/configuration/user/oidc/oidc.html#redirect-uris).
Authelia accepts only http and https in `redirect_uris`, according to the [doc](https://www.authelia.com/docs/configuration/identity-providers/oidc.html#redirect_uris) .
<!--
Describe the bug here.
-->

### Expected Behaviour
OIDC login from iOS app

<!--
Describe the behaviour your expect here.
-->

### Reproduction Steps
Configure owncloud to use authelia as IDP, add default iOS client as described [here](https://doc.owncloud.com/server/next/admin_manual/configuration/user/oidc/oidc.html#owncloud-desktop-and-mobile-clients) and start login flow from iOS app

<!--
1. Replace this step with your first step. Add additional steps below this.
-->

### Additional Information

Adding the `oc` uri sheme must resolve the issue, here is the full request coming from iOS app:
`GET/api/oidc/authorize?prompt=consent&response_type=code&code_challenge_method=S256&code_challenge=z7d2cS0bP6Sz03hDpeaiiJXMjQ3RgiAVfFEhVgQ4KFg&scope=openid offline_access email profile&redirect_uri=oc://ios.owncloud.com&client_id=mxd5OQDk6es5LzOzRvidJNfXLUZS2oN3oUFeXPP8LpPrhx3UroJFduGEYIBOxkY1HTTP/2.0 "Mozilla/5.0(iPhone;CPUiPhoneOS15_1likeMacOSX)AppleWebKit/605.1.15(KHTML,likeGecko)Version/15.1Mobile/15E148Safari/604.1"`

thank you
<!--
This section is for relevant additional information like; logs, configurations, environment information, etc.
-->
