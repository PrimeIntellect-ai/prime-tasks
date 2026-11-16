google.protobuf.Struct not working with list_value
When digging down a google.protobuf.Struct and using the list_value type as value evans doesn't dig down to the value selection of the list type. When reaching `circulated field was found` and then hitting `dig down` it will not show the type selection but instantly jump to the next `circulated field was found` entry.
```
<repeated> filter::dimension::fields::key (TYPE_STRING) => size
✔ dig down
✔ list_value
✔ dig down
✔ dig down
✔ dig down
✔ dig down
✔ dig down
✔ dig down
Use the arrow keys to navigate: ↓ ↑ → ←
? circulated field was found. dig down or finish? field: filter::dimension::fields::value::list_value::values ():
  ▸ dig down
    finish
```
My proto file section for the struct looks like the following.
```
google.protobuf.Struct dimension = 6;
```
