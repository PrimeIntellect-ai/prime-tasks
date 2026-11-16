Support field descriptions using field metadata
Additional metadata can be given to [dataclass fields](https://docs.python.org/3/library/dataclasses.html#dataclasses.field).

This could be used to provide a description of each field like so:

```python
@dataclass
class InventoryItem(JsonSchemaMixin):
    '''Class for keeping track of an item in inventory.'''
    name: str
    unit_price: float = field(metadata=dict(description="Unit price in £"))
    quantity_on_hand: int = 0
```
