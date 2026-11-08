Add display_title parameter to GHWorkflowRun model
**Describe the bug**
Now GHWorkflowRun model doesn't return **display_title** parameter of workflow run:  https://docs.github.com/en/rest/actions/workflow-runs?apiVersion=2022-11-28#list-workflow-runs-for-a-workflow

**Expected behavior**
Could you please add this parameter? I made pull for this https://github.com/hub4j/github-api/pull/1662
Thank you

### Additional contract requirements

- Expose the workflow run’s `display_title` value through the public Java accessor `GHWorkflowRun.getDisplayTitle()`; return `null` when the field is absent.
