optional output artifacts do not work on composite templates
Checklist:

 * [x] I've included the version.
 * [x] I've included reproduction steps.
 * [x] I've included the workflow YAML.
 * [x] I've included the logs.

Optional output artifacts are meant to handle the case when the file being created does not exist; they simply do not create the artifact. They work great for container and script templates. But this same functionality does not apply to output artifacts of composite (script/dag) templates, and it should.

Here's an example:
```
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: artifact-passing-
spec:
  entrypoint: artifact-example
  templates:
  - name: artifact-example
    steps:
    - - name: skip-artifact-generation
        template: conditional-whalesay
        arguments:
          parameters:
          - name: proceed
            value: false

  - name: whalesay
    container:
      image: docker/whalesay:latest
      command: [sh, -c]
      args: ["sleep 1; cowsay hello world | tee /tmp/hello_world.txt"]
    outputs:
      artifacts:
      - name: hello-art
        path: /tmp/hello_world.txt

  - name: conditional-whalesay
    inputs:
      parameters:
      - name: proceed
    steps:
    - - name: whalesay
        template: whalesay
        when: "{{inputs.parameters.proceed}}"
    outputs:
      artifacts:
      - name: hello-art
        from: "{{steps.whalesay.outputs.artifacts.hello-art}}"
        optional: true
```

Here are the logs when I run this (which should do nothing, but it fails).

```
STEP                                                    PODNAME  DURATION  MESSAGE
 ✖ layered-artifact-tt5jq (artifact-example)                               child 'layered-artifact-tt5jq[0].skip-artifact-generation' errored
 └---⚠ skip-artifact-generation (conditional-whalesay)                     Unable to resolve: {{steps.whalesay.outputs.artifacts.hello-art}}
     └---○ whalesay (whalesay)                                             when 'false' evaluated false
```

In this example, I want to produce an artifact at a lower level of nesting, then pass it to the higher level. However, I'm using this layering in order to only conditionally run this step (why do I want to do that? because it's [the only way](https://github.com/argoproj/argo/issues/2057) I can get a global output parameter into a WorkflowTemplate). I need the upper template to inherit the optionality of its output artifact from the lower template, but it doesn't work.

I've tried this in both Argo v2.4.1 and v2.6.2 and it unsurprisingly fails the same in both.

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

If you are impacted by this bug please add a 👍 reaction to this issue! We often sort issues this way to know what to prioritize.
