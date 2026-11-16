Bug or misunderstanding of word_order in convert methods
Look at this code:

```python
from pymodbus.client.mixin import ModbusClientMixin


original_values = [1.0, 2.0, 3.0]
registers = ModbusClientMixin.convert_to_registers(
    original_values, ModbusClientMixin.DATATYPE.FLOAT32, word_order="little"
)

converted_values = ModbusClientMixin.convert_from_registers(
    registers, ModbusClientMixin.DATATYPE.FLOAT32, word_order="little"
)
print("Original values:", original_values)
print("Converted registers:", registers)
print("Converted back values:", converted_values)
```

I expected this result:

```
Original values: [1.0, 2.0, 3.0]
Converted registers: [0, 16448, 0, 16384, 0, 16256]
Converted back values: [1.0, 2.0, 3.0]
```

But got:

```
Original values: [1.0, 2.0, 3.0]
Converted registers: [0, 16448, 0, 16384, 0, 16256]
Converted back values: [3.0, 2.0, 1.0]
```

I thought the "word_order" was meant to be used in order to specify how words are ordered when decomposing datatypes with more bytes. For example in a 4 byte float that will be transmited as 2 words I expected "word_order" to determine if the first word has the least significant portion (little) or the most significant part (big).

But checking at the code I can see all it does is reverse all the registers or something like that.

I guess I'm just misunderstanding something...

### Additional contract requirements

For fixed-width values that occupy multiple registers, `word_order="little"` determines the order of registers within each individual value. It does not reorder the values in a sequence. Converting a sequence to registers and back using the same word order preserves both the values and their sequence. The register list shown in the BASE example is inconsistent with its stated word-order meaning. Its corrected result is `[0, 16256, 0, 16384, 0, 16448]`: converting `[1.0, 2.0, 3.0]` as `FLOAT32` with little word order must preserve that value sequence when converted back.
