Bond order lost after serializing Structure
Hi,

It seems that Structure.__getstate__ does not include bond order in its output dictionary, as seen here:
https://github.com/ParmEd/ParmEd/blob/master/parmed/structure.py#L3836

As a result, bond order information is lost during serialization and deserialization. Could you please consider implementing a fix for this issue?

Thank you!
