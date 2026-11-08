AttributeError: 'PdfFileWriter' object has no attribute 'stream'
I am very happy to see that PyPDF2 is being maintained and released again - however, it seems that the latest release appears to contain a regression. We had an unpinned dependency on PyPDF2 in our library, and when 1.27.0 was released, we started seeing this error:

```
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:482: in write
    self._sweepIndirectReferences(externalReferenceMap, self._root)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:572: in _sweepIndirectReferences
    self._sweepIndirectReferences(externMap, realdata)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:548: in _sweepIndirectReferences
    value = self._sweepIndirectReferences(externMap, value)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:572: in _sweepIndirectReferences
    self._sweepIndirectReferences(externMap, realdata)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:548: in _sweepIndirectReferences
    value = self._sweepIndirectReferences(externMap, value)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:557: in _sweepIndirectReferences
    value = self._sweepIndirectReferences(externMap, data[i])
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:572: in _sweepIndirectReferences
    self._sweepIndirectReferences(externMap, realdata)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:548: in _sweepIndirectReferences
    value = self._sweepIndirectReferences(externMap, value)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:589: in _sweepIndirectReferences
    newobj = self._sweepIndirectReferences(externMap, newobj)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:548: in _sweepIndirectReferences
    value = self._sweepIndirectReferences(externMap, value)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:548: in _sweepIndirectReferences
    value = self._sweepIndirectReferences(externMap, value)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:589: in _sweepIndirectReferences
    newobj = self._sweepIndirectReferences(externMap, newobj)
../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:548: in _sweepIndirectReferences
    value = self._sweepIndirectReferences(externMap, value)
_ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _ _

self = <PyPDF2.pdf.PdfFileWriter object at 0x7f3f9fe45460>
externMap = {<ricecooker.utils.pdf.CustomPDFReader object at 0x7f3f9fec98b0>: {0: {116: IndirectObject(7, 0), 118: IndirectObject(6, 0), 119: IndirectObject(3, 0), 120: IndirectObject(5, 0)}}}
data = IndirectObject(8, 0)

    def _sweepIndirectReferences(self, externMap, data):
        debug = False
        if debug: print((data, "TYPE", data.__class__.__name__))
        if isinstance(data, DictionaryObject):
            for key, value in list(data.items()):
                origvalue = value
                value = self._sweepIndirectReferences(externMap, value)
                if isinstance(value, StreamObject):
                    # a dictionary value is a stream.  streams must be indirect
                    # objects, so we need to change this value.
                    value = self._addObject(value)
                data[key] = value
            return data
        elif isinstance(data, ArrayObject):
            for i in range(len(data)):
                value = self._sweepIndirectReferences(externMap, data[i])
                if isinstance(value, StreamObject):
                    # an array value is a stream.  streams must be indirect
                    # objects, so we need to change this value
                    value = self._addObject(value)
                data[i] = value
            return data
        elif isinstance(data, IndirectObject):
            # internal indirect references are fine
            if data.pdf == self:
                if data.idnum in self.stack:
                    return data
                else:
                    self.stack.append(data.idnum)
                    realdata = self.getObject(data)
                    self._sweepIndirectReferences(externMap, realdata)
                    return data
            else:
>               [HIDDEN]
E               AttributeError: 'PdfFileWriter' object has no attribute 'stream'

../../.virtualenvs/ricecooker_clean/lib/python3.9/site-packages/PyPDF2/pdf.py:575: AttributeError
```

It seems to be entirely internal to PyPDF2, so might be causing some issues for others as well.

### Additional contract requirements

- Writing a PDF with a page obtained from a reader must not raise an `AttributeError` because an indirect object's owner lacks a `stream` attribute.
