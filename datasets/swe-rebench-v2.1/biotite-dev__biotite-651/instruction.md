Bug: Deserialization of some CIF blocks
The `v1.0.0` release has a pretty serious bug for deserializing some CIF files.

**Description**:
When deserializing CIF files for some pdbs (e.g. [`5gam`](https://[files.rcsb.org/view/5GAM.cif](https://files.rcsb.org/view/5GAM.cif))) the deserialization fails to parse the lines correctly.

You can reproduce it e.g. for the `entity` field with
```python
import biotite.structure.io.pdbx as pdbx
from tempfile import gettempdir
import biotite.database.rcsb as rcsb

cif_file_path = rcsb.fetch("5gam", "cif", gettempdir())
cif_file = pdbx.CIFFile.read(cif_file_path)
cif_file.block["entity"]
category = cif_file.block["entity"]
column = category["id"]
data = column.data
print(data.array)

# Output
# ['1' '2' '3' '4' 'The 5'
# 'Small nuclear ribonucleoprotein-associated protein B'
#  'Small nuclear ribonucleoprotein E' 'Small nuclear ribonucleoprotein F'
# 'Small nuclear ribonucleoprotein G' 'Unknown polypeptide'
# 'Small nuclear ribonucleoprotein Sm D3'
# 'Small nuclear ribonucleoprotein Sm D1'
# 'Small nuclear ribonucleoprotein Sm D2' "GUANOSINE-5'-TRIPHOSPHATE"]
```

**Solution**:
[HIDDEN] Biotite versions prior to `1.0.0` do not have this commit and work fine.

### Additional contract requirements

When a CIF loop contains multiple fields per row, deserialization must keep each value associated with its corresponding field. In affected entity blocks, identifier values must remain in the entity identifier field rather than being placed in the description field, and descriptions must remain in their own field.
