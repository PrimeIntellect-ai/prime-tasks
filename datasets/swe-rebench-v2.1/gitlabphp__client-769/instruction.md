Add support for additional filters in the Deployment API
In https://docs.gitlab.com/ee/api/deployments.html there are additional filters available and I'd like to use at least a few of them...

I'll submit a MR shortly with the updates I think are needed...

### Additional contract requirements

- `Deployments::all($projectId, array $parameters = [])` must support a `status` parameter to filter deployment listings. Valid values are `created`, `running`, `success`, `failed`, `canceled`, and `blocked`.
- It must also support an `environment` parameter to filter deployment listings by environment name.
