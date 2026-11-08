Event callbacks are reassigned to an inner widget on each render
<!--
  Note: if the issue is a general React question, please check React Docs first: https://reactjs.org/docs
  If your question is about  DevExtreme widgets' APIs, use the DevExpress Support Center: https://www.devexpress.com/Support/Center
-->

### Issue Type
bug report

### Description
<!-- Specify what exactly the issue is related to (e.g. a component name) -->
Event callbacks are reassigned to an inner widget on each render. It causes performance issues and "Maximum callstack" errors

#### Current Behavior
Event callbacks are reassigned to an inner widget on each render
#### Expected Behavior
Event callbacks are reassigned to an inner widget only then callbacks changes
#### Demo
<!--
  If you provide a minimal demo of the problem\proposal, it helps us to solve it much faster.
  Paste the link to your online code editor (like https://stackblitz.com) below:
-->
https://codesandbox.io/s/j4m8y7km05

### Environment Details
<!--
Specify DevExtreme version, DevExtreme React Components version, React version and other environment details or notes you consider important.
-->
- devextreme version: latest
- devextreme-react version: latest
- react version: latest
