PopState event (history update) triggered by Luigi Client when updating context from Luigi Container
**Description**
`Luigi Container` is injected to the host application, it communicates with `Luigi Client` in a Microfrontend. Microfrontend is embedded in the host application via an iframe.

Whenever the host application updates a context (using https://github.com/SAP/luigi/blob/main/container/src/api/container-api.ts#L11), the Microfrontend receives it and dispatches a PopState event as well as replaces current state in browser history (https://github.com/SAP/luigi/blob/v2.7.5/client/src/lifecycleManager.js#L109-L110). It triggers some unexpected navigation issues in the Microfrontend integration.

Library versions:
- @luigi-project/container@1.0.0
- @luigi-project/client@2.7.5

**Expected result**

PopState event / history update are not triggered. Context update is not related to navigation, at least for such setup like Luigi Container+Luigi Client

**Actual result**

PopState event / history update happen.

**Steps to reproduce**

Details provided above

**Troubleshooting**
The only workaround I've found so far is to make a call with `isNavigateBack` flag. It doesn't have any side effects but according to source code it prevents history to be updated:
```ts
container.updateContext(context, {isNavigateBack: true});
```

I consider this as a workaround because this flag seems to be irrelevant here
