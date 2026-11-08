[Task] Update Karpenter to v0.13.2
### Description

Atm, we have Karpenter versioned pinned to 0.9.0. Upgrade this version to [0.13.2](https://github.com/aws/karpenter/releases/tag/v0.13.2)

Previous Reference ticket: #5023

Edit 18-08-2022:
AWS notified us of a new stable release of v0.15.0 yesterday so we'll be updating the minimum supported version to `0.15.0`

### Additional contract requirements

- Although the upstream edit calls 0.15.0 the “minimum supported version,” treat 0.15.0 as the maximum supported configuration version: accept Karpenter versions at or below 0.15.0 and reject newer versions.
- Update the Karpenter version shown in eksctl’s shipped example configuration and user documentation to 0.15.0.
