Migration script doesn't take exising context.* usage into account
When updating the panel to 5.0.0, the migration script does not take existing context.* usage into account, like in the 'Before content rendering', the following script:

```context.handlebars.registerHelper("containerId", () => `container-${context.panelData.request.panelId}`);```

is migrated to

```context.handlebars.registerHelper("containerId", () => `container-${context.context.panelData.request.panelId}`);```

therefore all panels will break after the migration. Please update the migration script to ignore existing usage of the new context.* structure.
