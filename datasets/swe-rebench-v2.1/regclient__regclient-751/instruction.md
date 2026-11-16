[Feature] Return a non-zero exit code if login fails
<!--
Note: Please search to see if an issue already exists for the bug you encountered.
-->

### Current Behavior

Calling `regctl registry login` with invalid credentials returns a zero exit code. When used in GitHub Actions, the step passes despite the login failure.

```
$ regctl registry login ghcr.io --user "<username>" --pass "<invalid-password>"
time="2024-05-25T06:01:28Z" level=warning msg="Changing login user for registry" host=docker.io new=<username> orig=githubactions
time="2024-05-25T06:01:28Z" level=warning msg="Changing login password for registry" host=docker.io
time="2024-05-25T06:01:28Z" level=warning msg="Failed to ping registry with credentials" err="failed to ping registry ghcr.io: unauthorized"
```

### Expected Behavior

Return a non-zero exit code so other commands are halted.

### Example Solution

<!--
Example: steps to result in the desired behavior:
1. In this environment...
2. With this config...
3. Run '...'
4. Desired result...
-->

### Version

0.6.1

### Environment

<!--
Please include:
- How you are running the tool: downloaded binary or from within a container
- Your platform: Linux, Windows, or Mac, x86 or ARM.
- Your registry: Docker Hub, ECR, GCR, ACR, Harbor, registry:2, etc.
-->

- Running as binary or container:
- Host platform:
- Registry description:

### Anything else

<!--
Links? References? Anything that will give us more context about the issue that you are encountering!
-->
https://github.com/regclient/regclient/blob/105aee14f726fd3348be77bba5c118cbce40aea9/cmd/regctl/registry.go#L312-L316
