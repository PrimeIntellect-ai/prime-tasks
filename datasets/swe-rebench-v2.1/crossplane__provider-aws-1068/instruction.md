Unneccessary API call ListTagsForResource in EKS Addons controller
### What happened?

The current controller implementation for EKS Addons uses `ListTagsForResource` to list the tags for API controller. This is not necessary since the tags are already provided through `DescribeAddon` which is called anyway.

The referred line: https://github.com/crossplane/provider-aws/blob/96a15aa76c5060da9769605acb4a3824ec521d0f/pkg/controller/eks/addon/setup.go#L138

### What environment did it happen in?

Current master (96a15aa76c5060da9769605acb4a3824ec521d0f)

### Additional contract requirements

When determining whether an EKS add-on is up to date, compare its configured tags with the tags included in the existing `DescribeAddon` response. Do not issue a separate `ListTagsForResource` request for this up-to-date check.
