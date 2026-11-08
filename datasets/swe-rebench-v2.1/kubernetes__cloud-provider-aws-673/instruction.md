Allow `ecr-credential-provider` to generate credentials for any registry
<!-- Please only use this template for submitting enhancement requests -->

**What would you like to be added**: Allow `ecr-credential-provider` to generate credentials for any registry (only base restrictions on `CredentialProviderConfig`)

**Why is this needed**:
Today `ecr-credential-provider`, is limited to `public.ecr.aws` , and registry url compliant with [ecrPattern](https://github.com/kubernetes/cloud-provider-aws/blob/master/cmd/ecr-credential-provider/main.go#L45).

In order to achieve this functionality we need to remove this restriction.

**End user use case** :
Using an EKS Cluster, we need to mirror public registry where SLA aren't garrantee or with some IP Rate limits restrictions.

In order to achieve that, I've setuped the followings :
- ECR Pull through cache to `public.ecr.aws` , `quay.io` and `registry.k8s.io`
- Containerd configured to mirror `public.ecr.aws` , `quay.io` and `registry.k8s.io` to my private ECR registry
- Private registry is hosted on another account (cross account scenario), on the same aws region
- aws-ecr-credential-provider configured to generate credentials for : `public.ecr.aws` , `quay.io` and `registry.k8s.io` with a config file like :
  ```json
  {
    "apiVersion": "kubelet.config.k8s.io/v1alpha1",
    "kind": "CredentialProviderConfig",
    "providers": [
      {
        "name": "ecr-credential-provider",
        "matchImages": [
          "*.dkr.ecr.*.amazonaws.com",
          "*.dkr.ecr.*.amazonaws.com/*",
          "*.dkr.ecr.*.amazonaws.com.cn",
          "*.dkr.ecr-fips.*.amazonaws.com",
          "*.dkr.ecr.*.c2s.ic.gov",
          "*.dkr.ecr.*.sc2s.sgov.gov",
          "quay.io",
          "public.ecr.aws",
          "registry.k8s.io"
        ],
        "defaultCacheDuration": "12h",
        "apiVersion": "credentialprovider.kubelet.k8s.io/v1alpha1"
      }
    ]
   }
  ```

* Current status : No credentials has been generated, and pull through cache aren't use
* Expected status : Credentials should be generated (for the current node , on the same aws region, or an explicit configuration on `CredentialProviderConfig`) , to allow my node to use my private registry mirror for public registry.


**Potential solution**:

I wonder if it's really needed to _generate an error here_ and not relying on SDK region behavior (and potential user configuration in provider configuration - `AWS_REGION` env variable in `CredentialProviderConfig` for exemple).

[HIDDEN]
[HIDDEN]
(further code updates will be probably needed ;-) )
[HIDDEN]
Relying on SDK default behavior will still throw an error when no region are configured (Eg. : `E0922 13:04:35.558288   57050 main.go:255] Error running credential provider plugin: MissingRegion: could not find region configuration` )

Ref.: https://github.com/kubernetes/cloud-provider-aws/pull/667#discussion_r1334174043

Sample working code modification : https://github.com/jBouyoud/cloud-provider-aws/commit/5a167d0ae233981db3a992dd767b1ff1f60fdcda

I'll be glad to help on this topic, please let me known how.
Regards

<!-- DO NOT EDIT BELOW THIS LINE -->
/kind feature

### Additional contract requirements

- A registry host selected by kubelet's credential-provider matching rules must not be rejected merely because it is not a private or public ECR host; subject to kubelet's base restrictions, the provider must be able to return credentials for it.
- If a host does not contain a private-ECR region, AWS region selection must be left to the AWS SDK configuration and defaults. For example, a configured `AWS_REGION` must be usable when requesting credentials for a non-ECR registry.
