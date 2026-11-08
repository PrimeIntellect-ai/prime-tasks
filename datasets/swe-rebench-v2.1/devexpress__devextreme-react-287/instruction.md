Incorrect integration options on widget creation
### Issue Type
bug report

### Description
<!-- Specify what exactly the issue is related to (e.g. a component name) -->
The issue is related to all widgets that use templates

#### Demo
See https://codesandbox.io/s/0199y6zxwv (18.2.4)
Compare the options the Form created with to the ones in the  example that used the v18.2.4-beta.1: https://codesandbox.io/s/y3q9n2n5yv

#### Current Behavior
IntegrationOptions added are incorrect:
```json
  "integrationOptions": {
    "templates": {
      "items[0].template": {},
      "items[1].template": {},
      "tabs[0].template": {}
    }
  },
  "items[0].template": "items[0].template",
  "items[1].template": "items[1].template",
  "tabs[0].template": "tabs[0].template"
```

#### Expected Behavior
Correct integrationOptions added (actually, templates not required in this case)

### Environment Details
<!--
Specify DevExtreme version, DevExtreme React Components version, React version and other environment details or notes you consider important.
-->
- devextreme-react version: 18.2.4 (regression, was PK in the 18.2.4-beta.1)

### Additional contract requirements

- When a collection nested component has nested option components as children rather than widget templates, widget creation must not register those children in `integrationOptions.templates` or synthesize template-path options for them.
