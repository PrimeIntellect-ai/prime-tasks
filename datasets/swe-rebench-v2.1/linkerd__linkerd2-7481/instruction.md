check: pull trust anchor certificate from `linkerd-identity-trust-roots`
### Is there an existing issue for this?

- [X] I have searched the existing issues

### What is the issue?

We introduced `linkerd-identity-trust-roots` as a configmap to help people have more control when it comes to managing trust anchors for their linkerd installation.

It was pointed out that when installing linkerd with `externalCA` and `externalIssuer` options, the check will fail when matching the trust bundle the proxies have with what's stored in linkerd's config. This is also the case when using extensions that have their own checks, e.g `viz`.

```
Cannot connect to Linkerd Viz: Some pods do not have the current trust bundle and must be restarted:
        * grafana-6fbc6dbf86-mz282
        * metrics-api-545b8d457b-jzdq7
        * prometheus-5d747596d-hfdlb
        * tap-85f7b8b69c-z6jxn
        * tap-injector-6fc7ddd46c-68pc6
        * web-75447677d7-cdl2z
Validate the install with: linkerd viz check
```

I think the problem comes from the fact that during installation, linkerd will store the trust root in both `linkerd-config` and `linkerd-identity-trust-roots`. When doing the check, the healthchecker will use the trust from `linkerd-config`. If linkerd is  installed without manually passing in the certificates, then there will be a mismatch.


### How can it be reproduced?

Install linkerd with a CA managed by cert-manager, or with an existing `linkerd-identity-trust-roots`.

### Logs, error output, etc

× viz extension proxies are healthy
    Some pods do not have the current trust bundle and must be restarted:
        * grafana-6fbc6dbf86-mz282
        * metrics-api-545b8d457b-jzdq7
        * prometheus-5d747596d-hfdlb
        * tap-85f7b8b69c-z6jxn
        * tap-injector-6fc7ddd46c-68pc6
        * web-75447677d7-cdl2z
    see https://linkerd.io/2.11/checks/#l5d-viz-proxy-healthy for hints

### output of `linkerd check -o short`

```text
N/A
```

### Environment

N/A

### Possible solution

[HIDDEN]

### Additional context

_No response_

### Would you like to work on fixing this bug?

_No response_

### Additional contract requirements

- When checking whether proxies have the current trust bundle, use the trust anchors in `linkerd-identity-trust-roots` as the reference, rather than trust data stored in `linkerd-config`.
