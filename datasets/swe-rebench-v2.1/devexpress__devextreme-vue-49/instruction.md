DxDataGrid.cellTemplate fails to work with a slot
### Current Behavior
produces an error
```console
[Vue warn]: Error in render: "TypeError: Converting circular structure to JSON"
```

### Expected Behavior
renders template correctly

### Steps to Reproduce
create a named slot within a dataGrid instance and try to use it as a cellTemplate

### Demo
```html
<template>
  <div>
      <dx-button
      text="test123"
      @click="testFunc"
      />
    <dx-data-grid
        :dataSource="items"
        :columns="columns"
        >
        <div slot="test" slot-scope="data" >
            <i>This is my template for {{data}}</i>
        </div>
    </dx-data-grid>
  </div>
</template>
<script>

import { DxDataGrid, DxButton, DxList } from 'devextreme-vue';

export default {
  props: ['items'],
  data() {
    return {
      columns: [
          {
              dataField: 'name',
              caption: 'Name'
          },
          {
              dataField: 'email',
              caption: 'E-mail'
          },
          {
              dataField: 'status',
              caption: 'Status'
          },
          {
              dataField: '',
              caption: 'Akcje',
              cellTemplate: "test"
          }
      ]
    };
  },
  methods: {
      testFunc: function() {
          console.log('testest1213123');
      }
  },
  components: {
    DxDataGrid,
    DxButton,
    DxList
  }
}
</script>
```
### Environment Details
DevExtreme 18.1.1-pre-18101
DevExtreme Vue 18.1.1-alpha.2

### Additional contract requirements

- When a slot template has class `custom-class`, the rendered element's `className` must be exactly `custom-class dx-template-wrapper`.
