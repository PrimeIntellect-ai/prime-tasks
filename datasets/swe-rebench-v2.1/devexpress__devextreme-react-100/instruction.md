List doesn't unmount old templates if they had dynamic root element
### Issue Type
bug report

#### Steps to Reproduce
1. Init List with ItemComponent option and 2 data items
2. Change ItemComponent's root element after 1s (loading simulation)
3. Change List's data items after 5s (filtration simulation)

#### Current Behavior
ReactList generates 2 templates after step 1 and 2 templates after step 2

#### Expected Behavior
ReactList generates 2 templates after step 1, removes 2 templates and generates 2 templates after step 2.

#### Demo
https://stackblitz.com/edit/devextreme-react-1dzhv6?file=index.js

### Environment Details
devextreme 18.1.1-pre-18093
devextreme-react 18.1.1-alpha.4
react 16.3.0
