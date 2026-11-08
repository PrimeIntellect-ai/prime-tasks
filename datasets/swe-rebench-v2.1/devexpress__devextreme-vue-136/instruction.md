Add default exports for components
### Issue Type
enhancement

### Description
<!-- Specify what exactly the issue is related to (e.g. a component name) -->
The issue is related to all the components

#### Current Behavior
```ts
export { DxBullet, DxBorder, DxFont, DxFormat, DxMargin, DxShadow, DxSize, DxTooltip };
```
#### Expected Behavior
```ts
export default DxBullet;
export { DxBullet, DxBorder, DxFont, DxFormat, DxMargin, DxShadow, DxSize, DxTooltip };
```

### Environment Details
<!--
Specify DevExtreme version, DevExtreme Vue Components version, Vue version and other environment details or notes you consider important.
-->
- devextreme-vue version: v18.1.4-alpha.7
