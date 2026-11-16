Logic operation fails on LogicValue wider than 127
https://github.com/intel/rohd/blob/344db0e18fa702eda056ed1ddbcda7717e154c17/lib/src/values/logic_value.dart#L783

The [HIDDEN] means that logic operations can fail when LogicValues are wide.
The limit appears to be 128.

### Additional contract requirements

- Operations on `LogicValue`s wider than 127 bits must complete successfully and produce correct results rather than fail.
