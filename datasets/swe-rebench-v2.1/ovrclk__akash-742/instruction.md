events: use consistent tense
As can be seen [here](https://github.com/ovrclk/akash/blob/3310cc668be406a19029ce458831a53f16345198/events/publish_test.go#L17-L34), only `market` events are past-tense.

Either make them all past-tense (`"*created"` I _think_ this is better) or not (`"*create"`)

### Additional contract requirements

All module events use past-tense action names. The deployment module emits events whose action names are `deployment-created`, `deployment-updated`, `deployment-closed`, and `group-closed`; the provider module emits events whose action names are `provider-created`, `provider-updated`, and `provider-deleted`.

The deployment module exposes these public constructors and event types in `x/deployment/types`:
- `NewEventDeploymentCreated(id DeploymentID) EventDeploymentCreated`
- `NewEventDeploymentUpdated(id DeploymentID) EventDeploymentUpdated`
- `NewEventDeploymentClosed(id DeploymentID) EventDeploymentClosed`
- `NewEventGroupClosed(id GroupID) EventGroupClosed`

The provider module exposes these public constructors and event types in `x/provider/types`:
- `NewEventProviderCreated(owner sdk.AccAddress) EventProviderCreated`
- `NewEventProviderUpdated(owner sdk.AccAddress) EventProviderUpdated`
- `NewEventProviderDeleted(owner sdk.AccAddress) EventProviderDeleted`
