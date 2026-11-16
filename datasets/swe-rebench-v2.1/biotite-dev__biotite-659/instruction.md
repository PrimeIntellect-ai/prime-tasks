The format of the mmCIF file after changing the block and saving is broken
Hello,

'd like to report a probable error. When I change a block in the mmCIF file and save it, a format break occurs. Items are written directly after the # character instead of on the next line. For example, instead of

```
data_9BFL
#
_entry.id   9BFL
#
_audit_conform.dict_name       mmcif_pdbx.dic
_audit_conform.dict_version    5.393
_audit_conform.dict_location   http://mmcif.pdb.org/dictionaries/ascii/mmcif_pdbx.dic
#
...
```

is written to the file

```
data_9BFL
#
_entry.id   9BFL
# _audit_conform.dict_name       mmcif_pdbx.dic
_audit_conform.dict_version    5.393
_audit_conform.dict_location   http://mmcif.pdb.org/dictionaries/ascii/mmcif_pdbx.dic
# loop_
_database_2.database_id
...
```

Code to reproduce (Used PDB can be downloaded from [here](https://www.rcsb.org/structure/9BFL):
``` python
import biotite.structure.io.pdbx as mmCIF
import biotite.structure as structure
import hydride

mmCIF_file = mmCIF.CIFFile.read("9bfl.cif")
protein = mmCIF.get_structure(mmCIF_file,
                              model=1,
                              extra_fields=["charge"],
                              include_bonds=True)
protein = protein[protein.element != "H"]  # remove all hydrogens
protein_with_hydrogens, _ = hydride.add_hydrogen(protein)
mmCIF_file_with_hydrogens = mmCIF.CIFFile()
mmCIF.set_structure(mmCIF_file_with_hydrogens, protein_with_hydrogens)
mmCIF_file.block["atom_site"] = mmCIF_file_with_hydrogens.block["atom_site"]
mmCIF_file.write("9bfl_protonated.cif")
```
