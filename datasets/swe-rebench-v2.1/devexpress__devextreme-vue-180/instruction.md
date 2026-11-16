Duplicate Configuration._nestedConfigurations  added on each render
### Issue Type
bug report

### Description
The issue is related to all the components

#### Steps to Reproduce
e.g. DxPopup - DxToolbarItem
- add a DxPopup instance with a single DxToolbarItem
- check $_config._nestedConfigurations (one object)
- force Popup rerender (e.g. hide it)
- check $_config._nestedConfigurations (two object)

#### Current Behavior
duplicate nested configuration

#### Expected Behavior
single nested configuration for each config-component

### Environment Details
- devextreme-vue version: 18.1.7-alpha.10
