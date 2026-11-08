Getting playwright error when trying to saml2aws login
Hey,

Getting an error when I login to saml2aws.

Error:
```
~ saml2aws login
Using IdP Account default to access Browser `URL`
To use saved password just hit enter.
? Username `username`
? Password

Authenticating as `username` ...
Error authenticating to IdP.: could not start driver: fork/exec /Users/`username`/Library/Caches/ms-playwright-go/1.20.0-beta-1647057403000/playwright.sh: no such file or directory
```

Steps:
```
brew install saml2aws
saml2aws configure
saml2aws login
```

Version:
```
~ saml2aws --version
2.36.5
```

### Additional contract requirements

- The browser Identity Provider account configuration type `IDPAccount` in package `pkg/cfg` has a public field `BrowserDriverDir string`. It names the directory where Playwright should look for, or install, its browser driver binaries.
- The login request type `LoginDetails` in package `pkg/creds` has a public field `DownloadBrowser bool`. When it is true, `Authenticate` installs the Playwright browser drivers before launching the browser.
- When `DownloadBrowser` is false and `BrowserDriverDir` points to a directory that does not contain browser drivers, `Authenticate` returns an error containing `could not start driver`.
