Query not refetching when enabled becomes 'true' and different instance is disabled
**Describe the bug**
I have 2 Components using the same query. At one point one instance changes the enabled flag to true while the other stays false. The query is not executed.

**To Reproduce**
I created a CodeSandbox: https://codesandbox.io/s/zen-almeida-g2o5z
Click the button to enable one of the queries => nothing happens. If you remove the <DisabledQuery /> component it works as expected.

**Expected behavior**
A query fetches when **any** instance is enabled.
