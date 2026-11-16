Form: Tab render prop not working
<!--
  Note: if the issue is a general React question, please check React Docs first: https://reactjs.org/docs
  If your question is about  DevExtreme widgets' APIs, use the DevExpress Support Center: https://www.devexpress.com/Support/Center
-->

### Issue Type
Bug Report

### Description
Form: Tab render prop not taken into account

We have a Devextreme-React form, using tabs to split it into section (Form/TabbedItem).
At some places, we have to render custom React components. Tabs and GroupItem provide render props that unfortunately do not seem to be taken into account, or sometime work in surprising ways.

The same things using template (and JQuery) props seem to work fine.

#### Steps to Reproduce
Create a Form with a Nested TabbedItem. Inside the TabbedItem
- create a Tab and use the render/tabRender/component/tabComponent props to render custom content.
- create a GroupItem inside a Tab and use the render/component props to render custom content.

#### Current Behavior
Custom content is not rendered; the render props does not seem to be ever called (that can be checked with a breakpoint).

More surprising results can be observed when specifying multiple GroupItem inside a Tab; some GroupItems seem to escape the tab (cf. the demo below)

#### Expected Behavior
The component should call the render function and render the custom component.

#### Demo
Please see https://stackblitz.com/edit/react-aukapj

### Environment Details
<!--
Specify DevExtreme version, DevExtreme React Components version, React version and other environment details or notes you consider important.
-->
- devextreme version: 18.2.4
- devextreme-react version: 18.2.4
- react version: 16.5.0

### Additional contract requirements

Nested configuration components must propagate template option paths through arbitrary
nesting levels. When a Tab is nested inside a TabbedItem and a GroupItem is nested
inside that Tab, the render-related props (`render`, `tabRender`, `component`,
`tabComponent`) must be invoked and must render the supplied custom React content. The
generated template option keys must reflect the full nesting, for example
`items[0].tabs[0].tabTemplate` and `items[0].tabs[0].items[0].template`.
