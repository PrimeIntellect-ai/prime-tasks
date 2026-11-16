SlideOutView doesn't support scrollable content
<!--
  Note: if the issue is a general React question, please check React Docs first: https://reactjs.org/docs
  If your question is about  DevExtreme widgets' APIs, use the DevExpress Support Center: https://www.devexpress.com/Support/Center
-->

### Issue Type
<!-- E.g. 'question', 'bug report', 'feature request' -->
"bug report"
### Description
<!-- Specify what exactly the issue is related to (e.g. a component name) -->
The issue is related to SlideOutView

#### Steps to Reproduce
<!-- If the current behavior is a bug, please provide the steps to reproduce -->
See demo to reproduce:
1) Pay attention to .dx-template-wrapper height. It is equal "auto" and prevent children with % as size
#### Current Behavior

#### Expected Behavior

#### Demo
<!--
  If you provide a minimal demo of the problem\proposal, it helps us to solve it much faster.
  Paste the link to your online code editor (like https://stackblitz.com) below:
-->
https://stackblitz.com/edit/devextreme-react-c7t368?file=index.js
### Environment Details
<!--
Specify DevExtreme version, DevExtreme React Components version, React version and other environment details or notes you consider important.
-->
- devextreme version: 18.1.6-pre-18220
- devextreme-react version:  18.1.5-alpha.10 (regression, was OK in the alpha.9)
- react version: 16.4.2

### Additional contract requirements

- Templated content rendered by widgets (including `SlideOutView`) must allow children with percentage-based heights to size relative to the available widget container height.
- When templated content is removed through the widget’s normal removal lifecycle, its associated template state and content must be cleaned up.
