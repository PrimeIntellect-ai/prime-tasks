Target addresses of gRPC services must be configurable
Mainly in the assessment and collector service.

### Additional contract requirements

The assessment service must let callers configure the outgoing gRPC target for both the Evidence Store and the Orchestrator. Its public service options are `WithEvidenceStoreAddress` and `WithOrchestratorAddress`.

The collector (discovery) service must let callers configure the outgoing gRPC target for the Assessment service. Its public service option is `WithAssessmentAddress`.
