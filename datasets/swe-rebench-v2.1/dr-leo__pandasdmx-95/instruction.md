Pretty-print Message subclasses
Per @dr-leo, identified in discussion of #72:

`Message` and subclasses have attributes that may be empty. For instance:
https://github.com/dr-leo/pandaSDMX/blob/a670198f45f90777d26b5b83c8d9e171b266ff6b/pandasdmx/message.py#L65-L73
…if there is no OrganisationScheme provided in a particular StructureMessage, then the `.organisation_scheme` dictionary is empty.

In order to provide a good user experience for interactive use, override `__str__` and/or `__repr__` on these classes to print something like this (inspired by xarray):
```
StructureMessage:
     Header: [some header info]
     Dataflows (12): 'DATAFLOW1' 'DATAFLOW2' 'DATAFLOW' ...
     Codelists (3): 'CL_FOO' 'CL_BAR' 'CL_BAZ'
```
This shows, at a glance:
- which attributes contain actual (meta)data,
- the number of objects in each, and
- a quick visual indication of some of the IDs.

### Additional contract requirements

- ``Header.__repr__`` returns ``<Header>`` followed by one ``<field>: <value>``
  line for each non-null header attribute (``error``, ``id``, ``prepared``,
  ``receiver``, ``sender``).
- ``StructureMessage.__repr__`` appends one summary line per non-empty
  ``DictLike`` attribute, of the form ``<ValueClassName> (<count>): <IDs>``,
  where ``<count>`` is the number of objects and ``<IDs>`` lists their keys.
  Empty ``DictLike`` attributes produce no line.
- ``DataMessage.__repr__`` appends a line ``DataSet (<N>)`` (where ``<N>`` is
  the number of ``DataSet`` objects) and summaries of ``dataflow`` and
  ``observation_dimension``.
- ``Message.__repr__`` includes the header representation and, when non-null,
  summaries of the ``footer`` and ``response`` attributes.
