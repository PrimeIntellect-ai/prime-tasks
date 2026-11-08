Missing Workflow Job's running machine type (ubuntu, windows, macos)
Hello,
I need to find Workflow Job's running machine type (ubuntu, windows, macos). Github Api has labels property which includes that information. It seems like you did not provide **labels** information of GHWorkflowJob. Can you provide that or do you have information about job's running mactine type already? Thank you for your supports...

### Additional contract requirements

Callers must be able to retrieve the labels reported for a workflow job through the public `GHWorkflowJob.getLabels()` accessor. The returned labels identify the job's runner type and may contain values such as `ubuntu-latest`.
