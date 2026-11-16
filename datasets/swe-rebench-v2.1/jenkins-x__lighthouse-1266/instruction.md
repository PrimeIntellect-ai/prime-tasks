Params declared in pre/postsubmit config are not passed to LighthouseJobSpec
It appears that the `pipeline_run_params` declared in the presubmit/postsubmit config in trigger.yaml are not copied to the generated LighthouseJobSpec and are therefore not available later to the subsequent code that generates the PipelineRun resource.

I had a browse of the source code and it looks like the bug is caused here:
https://github.com/jenkins-x/lighthouse/blob/860dc3b15d148e9437661d8172798a9ea0192720/pkg/jobutil/jobutil.go#L160-L174
as the line [HIDDEN] is missing.

### Additional contract requirements

When presubmit or postsubmit configuration declares multiple pipeline run parameters, every configured parameter name and value template must be present in the generated LighthouseJobSpec; parameters after the first must not be dropped.
