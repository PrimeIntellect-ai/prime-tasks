allowed-hosts failing on urls with port and no scheme
<!--- Provide a general summary of the issue in the Title above -->
Hi there! We've been using lockfile-lint at our company. We have been specifying `--allowed-hosts` with a domain and port, like this: `nexus.example.com:8089`. Up until yesterday, this worked fine:

```
npx lockfile-lint --path package-lock.json --allowed-hosts nexus.example.com:8089 registry.npmjs.org
```

As of today, the above command results in false positives that look like this:
```
detected invalid host(s) for package: zero-crossings@1.0.1-72cbc63a942ee565369f9524fb69fdbe2d885364
    expected: ,registry.npmjs.org
    actual: nexus.example.com:8089
```
(Note the leading comma in the "expected" value. It seems that this CLI argument is being parsed incorrectly?)

Changing `nexus.example.com:8089` to `https://nexus.example.com:8089` makes it work again.

## Expected Behavior

Expected allowed-hosts not to require a scheme.

<!--- If you're describing a bug, tell us what should happen -->
<!--- If you're suggesting a change/improvement, tell us how it should work -->

## Current Behavior

When using a port in an allowed-host, it doesn't work unless you use a scheme as well. And if that's a feature not a bug, then the error message could be improved.

<!--- If describing a bug, tell us what happens instead of the expected behavior -->
<!--- If suggesting a change/improvement, explain the difference from current behavior -->


## Your Environment

<!--- Include as many relevant details about the environment you experienced the bug in -->

- Library Version used: 4.3.3
- Node.js version (e.g. Node.js 5.4): 12.9.1, npm 6.12.1
- Operating System and version (desktop or mobile): linux
