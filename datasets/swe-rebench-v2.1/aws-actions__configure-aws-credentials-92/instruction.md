Need for sts:TagSession Permission
We are using the [AWS Deploy CloudFormation Stack Github Action](https://github.com/marketplace/actions/aws-cloudformation-deploy-cloudformation-stack-action-for-github-actions) to configure AWS accounts that are created via AWS Organizations.

Of course, we are first using this action for credential configuration and assuming a role. However, this credential action does [session tagging](https://github.com/aws-actions/configure-aws-credentials/blob/master/index.js#L49) which requires the `sts:TagSession` permission. This need for tagging is of course [documented in the readme of this action](https://github.com/marketplace/actions/configure-aws-credentials-action-for-github-actions#permissions-for-assuming-a-role). However, in our case, the tag is needed in the trust policy of the `OrganizationAccountAccessRole` in the member account that is created by AWS Organizations.

This results in manual effort/intervention to our automated process. We have to configure the root user for the member account created by AWS Organizations to add the permission to the trust policy.

Would it be possible to make the session tagging optional?

### Additional contract requirements

- The action declares an optional GitHub Action input named `role-skip-session-tagging`.
- When `role-skip-session-tagging` is true, the AssumeRole request omits session tags (its `Tags` property is `undefined`).
- When `role-skip-session-tagging` is false or not provided, the AssumeRole request includes the standard set of GitHub-derived session tags.
