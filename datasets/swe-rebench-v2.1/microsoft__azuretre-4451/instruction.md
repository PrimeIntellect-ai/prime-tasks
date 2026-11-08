Pipeline substitution only works when values are marked as updatable so not for install.
When passing values into a resource in a pipeline, the code only allows input for values marked as updatable. This means if need to pass values into the app at install it does not work.

For example `subscription_id` into a workspace, needed by #1073 cc @askew

And `log_analytics_workspace_name` as needed by #4341

PR to come.

### Additional contract requirements

- The module `resources/strings.py` defines the resource action constants `RESOURCE_ACTION_INSTALL` (value `"install"`) and `RESOURCE_ACTION_UPDATE`.
- `ResourceRepository.validate_patch(resource_patch, resource_template_repo, resource_template, resource_action)` accepts a `resource_action` argument. When `resource_action` is `RESOURCE_ACTION_INSTALL`, every property defined by the template is accepted, including properties that are not marked updateable; for any other action only properties marked updateable are accepted. Unknown properties and invalid values are rejected with `jsonschema.exceptions.ValidationError`.
- `ResourceRepository.patch_resource(resource, resource_patch, resource_template, etag, resource_template_repo, resource_history_repo, user, resource_action, force_version_update=False)` accepts a `resource_action` argument and validates the patch according to it.
- A pipeline step's declared resource action is used when applying that step's patch; when a step does not declare a resource action and the pipeline is being run for an install, the step is applied as an install action.
