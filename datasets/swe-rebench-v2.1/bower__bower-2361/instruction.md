bower install ends in `unable to access 'https://github.com/jquery/jquery-dist.git/': SSL: CA certificate set, but certificate verification is disabled`
I am not able to install (anything?) with bower. I am trying to use the public GitHub and a popular library but I get error: `git ls-remote --tags --heads https://github.com/jquery/jquery-dist.git", exit code of #128 fatal: unable to access 'https://github.com/jquery/jquery-dist.git/': SSL: CA certificate set, but certificate verification is disabled`
# Details:

Additional error details:

**Output of `bower -v && npm -v && node -v`:**

```
1.7.9
3.10.3
v6.5.0
```

**Additional environment details (proxy, private registry, etc.):**
I have disabled everything I know.

**Steps to reproduce the issue:**
1.  `bower install jquery`

**Describe the results you received:**

```
bower install jquery
bower jquery#*              not-cached https://github.com/jquery/jquery-dist.git#*
bower jquery#*                 resolve https://github.com/jquery/jquery-dist.git#*
bower jquery#*                 ECMDERR Failed to execute "git ls-remote --tags --heads https://github.com/jquery/jquery-dist.git", exit code of #128 fatal: unable to access 'https://github.com/jquery/jquery-dist.git/': SSL: CA certificate set, but certificate verification is disabled
```

**Describe the results you expected:**

I expected Bower to finish the without errors.

**Additional information:**
1. I have tried this in the command without and no errors. It shows `Content-Type: application/x-git-upload-pack-advertisement`

```
GIT_CURL_VERBOSE=2 git ls-remote --heads https://github.com/jquery/jquery-dist.git
```
1. I was sneaking in the source code and the error comes from [cmd.js#L102](https://github.com/bower/bower/blob/master/lib/util/cmd.js#L102) called by [GitRemoteResolver.js#L253](https://github.com/bower/bower/blob/master/lib/core/resolvers/GitRemoteResolver.js#L253) **I wonder why the command succeeds in my terminal but fails when done by bower?**
2. If it matters here is my bower.json:

```
{
  "name": "webcomp",
  "authors": [
    "me <me@email.com>"
  ],
  "description": "",
  "main": "",
  "license": "MIT",
  "homepage": "",
  "private": true,
  "ignore": [
    "**/.*",
    "node_modules",
    "bower_components",
    "test",
    "tests"
  ]
}
```
