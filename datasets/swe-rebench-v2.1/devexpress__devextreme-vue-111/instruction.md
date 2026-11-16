Support non-scoped slots for templates
For some cases, `slot-scope` in template looks [excess](
https://codesandbox.io/s/0wvq6vnl).
```html
<dx-popup
  contentTemplate="contentTemplate"
  :visible="true"
>
   <div slot="contentTemplate" slot-scope="_">
      This is content template
   </div>
</dx-popup>
```
I tnink we should support syntax without `slot-scope`.
