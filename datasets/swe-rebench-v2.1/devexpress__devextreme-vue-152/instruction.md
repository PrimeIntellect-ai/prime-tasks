Add .sync support for nested components
<!--
  Note: if the issue is a general Vue question, please check Vue Docs first: https://vuejs.org/v2/guide/
  If your question is about  DevExtreme widgets' APIs, use the DevExpress Support Center: https://www.devexpress.com/Support/Center
-->

### Issue Type
<!-- E.g. 'question', 'bug report', 'feature request' -->
feature request
### Description
<!-- Specify what exactly the issue is related to (e.g. a component name) -->
It would be great to support `.sync` syntax in nested components.
Use case:
```html
<dx-data-grid>
  <dx-column dataField="staticColumn1"/>
  <dx-column dataField="orderedColumn" :sortOrder.sync="sortOrter" />
  <dx-column dataField="staticColumn2"/>
</dx-data-grid>
```
