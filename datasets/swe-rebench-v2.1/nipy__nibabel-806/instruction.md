incorrect datatype in GIFTI output (INT64 instead of INT32)
Having an issue with NODE_INDEX. To reproduce:

```Python
#! /usr/bin/env python

import sys
import numpy as np
import nibabel

print("nibabel.__version__ =", nibabel.__version__)

idx = np.arange(10)

da = nibabel.gifti.GiftiDataArray(idx,
                                  intent = 'NIFTI_INTENT_NODE_INDEX',
                                  datatype = 'NIFTI_TYPE_INT32')

gim = nibabel.gifti.gifti.GiftiImage(darrays = [da])
nibabel.save(gim, "idx.gii")

gim = nibabel.load("idx.gii")
print(gim.darrays[0].data)

da = nibabel.gifti.GiftiDataArray(idx, encoding = 'GIFTI_ENCODING_ASCII',
                                  intent = 'NIFTI_INTENT_NODE_INDEX',
                                  datatype = 'NIFTI_TYPE_INT32')

gim = nibabel.gifti.gifti.GiftiImage(darrays = [da])
nibabel.save(gim, "idx.gii")

gim = nibabel.load("idx.gii")
print(gim.darrays[0].data)
```

What I get here, on a 64-bit machine:

```
nibabel.__version__ = 3.0.0dev
[0 0 1 0 2 0 3 0 4 0 5 0 6 0 7 0 8 0 9 0]
[0 1 2 3 4 5 6 7 8 9]
```

[HIDDEN]

Here's a fix:

```Diff
diff --git a/nibabel/gifti/gifti.py b/nibabel/gifti/gifti.py
index 22d6449e..e1149647 100644
--- a/nibabel/gifti/gifti.py
+++ b/nibabel/gifti/gifti.py
@@ -464,7 +464,7 @@ class GiftiDataArray(xml.XmlSerializable):
         # write data array depending on the encoding
         dt_kind = data_type_codes.dtype[self.datatype].kind
         data_array.append(
-            _data_tag_element(self.data,
[HIDDEN]
                               gifti_encoding_codes.specs[self.encoding],
                               KIND2FMT[dt_kind],
                               self.ind_ord))
```

Perhaps the bug is that self.data is int64 already, but I'm not sure about that.
Anyway with this change the output is the same as with ASCII encoding.

### Additional contract requirements

- Serialized GIFTI data must conform to its declared datatype. After saving and reloading, the data values and dtype must be consistent with that datatype across supported encodings, including ASCII and binary.
