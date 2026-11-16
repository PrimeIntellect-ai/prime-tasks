Add controller mode where only WFs from WFTemplates can be submitted
# Summary

Add a "restricted" mode to the `workflow-controller` where only `Workflows` that submit `WorkflowTempaltes` can be executed. Depends on the top-level `WorkflowTemplate` reference PR #2556

# Motivation

After #2556 is completed, users will be able to submit Workflows that are simply a reference to a `WorkflowTemplate`.

Some users might want to take advantage of this feature to add a "restricted" controller, in which users of said controller may only submit `Workflows` that already exist in the cluster as `WorkflowTemplates` and may not submit any user-defined `Workflows`. These `WorkflowTemplates` would be maintained by the "cluster owner".

# Proposal

Allow the `workflow-controller` to start with a flag setting it as restricted, then only accept `Workflows` that contain a workflow reference as defined in #2556

Feature idea by @jessesuen

---
<!-- Issue Author: Don't delete this message to encourage other users to support your issue! -->
**Message from the maintainers**:

If you wish to see this enhancement implemented please add a 👍 reaction to this issue! We often sort issues this way to know what to prioritize.

### Additional contract requirements

- When a Workflow without `workflowTemplateRef` is processed in Strict or Secure mode, its status phase must be `NodeError` and its status message must be exactly `workflows must use workflowTemplateRef to be executed when the controller is in reference mode`. In Secure mode, if the referenced WorkflowTemplate specification changes during execution, the Workflow status phase must be `NodeError` and its status message must be exactly `workflowTemplateRef reference may not change during execution when the controller is in reference mode`.
- Add a public type `WorkflowRestrictions` in package `config` with an exported field `TemplateReferencing` of type `TemplateReferencing`.
- Add public constants `TemplateReferencingStrict` and `TemplateReferencingSecure` of type `TemplateReferencing` in package `config`, with values `Strict` and `Secure` respectively.
- Add an exported field `WorkflowRestrictions *WorkflowRestrictions` to the controller configuration type `Config` in package `config`.
- Add a public method `MustUseReference() bool` on `*WorkflowRestrictions` in package `config` that reports whether the controller requires every Workflow to reference a WorkflowTemplate: true when `TemplateReferencing` is Strict or Secure, false otherwise, including a nil receiver.
- Add a public method `MustNotChangeSpec() bool` on `*WorkflowRestrictions` in package `config` that reports whether the controller must reject a Workflow whose referenced WorkflowTemplate specification changes during execution: true when `TemplateReferencing` is Secure, false otherwise, including a nil receiver.
- Add public functions `LoadTestWorkflowTemplate(path string) *wfv1.WorkflowTemplate` and `LoadWorkflowTemplateFromBytes(yamlBytes []byte) *wfv1.WorkflowTemplate` in package `test` that read a WorkflowTemplate YAML file or byte slice and return the unmarshalled object.
- - In Strict mode, when a valid referenced WorkflowTemplate's specification has changed before the Workflow is processed, that change must not cause rejection: the Workflow's status phase must be `NodeRunning`.
