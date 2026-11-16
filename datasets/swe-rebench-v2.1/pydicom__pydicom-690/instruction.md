Private tags -- Exception: unhashable type 'list'
#### Description
While reading a dicom get problems with private tags, error:
TypeError: With tag (50f1, 100a) got exception: unhashable type: 'list'


#### Steps/Code to Reproduce
Simply read file with dicomio.read_file and print.

#### Expected Results
Print dicom items.

#### Actual Results
TypeError: With tag (50f1, 100a) got exception: unhashable type: 'list'
Traceback (most recent call last):
  File "/home/michele/.virtualenvs/odoo10.0/lib/python2.7/site-packages/pydicom/tag.py", line 30, in tag_in_exception
    yield
  File "/home/michele/.virtualenvs/odoo10.0/lib/python2.7/site-packages/pydicom/dataset.py", line 974, in _pretty_str
    strings.append(indent_str + repr(data_element))
  File "/home/michele/.virtualenvs/odoo10.0/lib/python2.7/site-packages/pydicom/dataelem.py", line 388, in __repr__
    return str(self)
  File "/home/michele/.virtualenvs/odoo10.0/lib/python2.7/site-packages/pydicom/dataelem.py", line 293, in __str__
    self.description()[:self.descripWidth],
  File "/home/michele/.virtualenvs/odoo10.0/lib/python2.7/site-packages/pydicom/dataelem.py", line 353, in description
    self.tag, self.private_creator)
  File "/home/michele/.virtualenvs/odoo10.0/lib/python2.7/site-packages/pydicom/datadict.py", line 279, in private_dictionary_description
    return get_private_entry(tag, private_creator)[2]
  [HIDDEN]
TypeError: unhashable type: 'list'


#### Versions
Linux-4.17.2-200.fc28.x86_64-x86_64-with-fedora-28-Twenty_Eight
('Python', '2.7.15 (default, May 16 2018, 17:50:09) \n[GCC 8.1.1 20180502 (Red Hat 8.1.1-1)]')
('numpy', '1.13.1')
('pydicom', '1.1.0')

### Additional contract requirements

- Private data elements must never be resolved through the DICOM repeater dictionary, even when their group and element numbers fall inside a repeater range. When such elements are read with Implicit VR Little Endian (so the raw element carries no VR), the following observable results must hold:
  - A private creator element (element number less than 0x0100) is described by ``DataElement.name`` as ``"Private Creator"`` and has VR ``"LO"``.
  - A private data element whose private creator is known and present in pydicom's private dictionary is described by ``DataElement.name`` using that private dictionary entry, wrapped in square brackets. In particular:
    - element (50f1,100a) with private creator ``"FDMS 1.0"`` is described as ``"[FNC Parameters]``;
    - element (6021,1200) with private creator ``"PAPYRUS 3.0 "`` is described as ``"[Overlay ID]``.
  - A private data element that is not found in the private dictionary has VR ``"UN"``.
- For the private data elements (50f1,100a) with private creator ``"FDMS 1.0"`` and (6021,1200) with private creator ``"PAPYRUS 3.0 "``, the VR must be ``"UN"``.
- Printing a dataset containing the reported private tags must complete without the reported TypeError.
