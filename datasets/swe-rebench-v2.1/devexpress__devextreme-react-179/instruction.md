List groupComponent does not send key value from grouped dataSource
### Issue Type
bug report

### Description
The issue is related to grouped List

#### Current Behavior
key value is undefined in groupComponent

#### Expected Behavior
key value has value from grouped dataSource

#### Demo
https://stackblitz.com/edit/devextreme-react-71rsvj?file=index.js

### Additional contract requirements

- A template component receives the key value of the data item it renders as the `dxkey` prop. The reserved React `key` prop is not passed to the template component.
- For a grouped List, the `groupComponent` receives the key value from the grouped data source as the `dxkey` prop.
