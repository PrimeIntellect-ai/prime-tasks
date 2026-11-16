Trouble using the `default_experiment`
I have ran into two issues trying to set the `default_experiment` using the `DefaultExperiment` class.

First, the xml parser is throwing an error regarding serializing the floats specified in the start/stop time fields, as such:
```
Traceback (most recent call last):
  File "/usr/lib/python3.8/xml/etree/ElementTree.py", line 1076, in _escape_attrib
    if "&" in text:
TypeError: argument of type 'float' is not iterable

During handling of the above exception, another exception occurred:

Traceback (most recent call last):
  File ".../bin/pythonfmu", line 8, in <module>
    sys.exit(cli_main())
  File "...lib/python3.8/site-packages/pythonfmu/__main__.py", line 55, in cli_main
    execute(**options)
  File "...lib/python3.8/site-packages/pythonfmu/builder.py", line 184, in build_FMU
    xml_str = parseString(tostring(xml, "UTF-8"))
  File "/usr/lib/python3.8/xml/etree/ElementTree.py", line 1133, in tostring
    ElementTree(element).write(stream, encoding,
  File "/usr/lib/python3.8/xml/etree/ElementTree.py", line 772, in write
    serialize(write, self._root, qnames, namespaces,
  File "/usr/lib/python3.8/xml/etree/ElementTree.py", line 937, in _serialize_xml
    _serialize_xml(write, e, qnames, None,
  File "/usr/lib/python3.8/xml/etree/ElementTree.py", line 930, in _serialize_xml
    v = _escape_attrib(v)
  File "/usr/lib/python3.8/xml/etree/ElementTree.py", line 1099, in _escape_attrib
    _raise_serialization_error(text)
  File "/usr/lib/python3.8/xml/etree/ElementTree.py", line 1053, in _raise_serialization_error
    raise TypeError(
TypeError: cannot serialize 0.0 (type float)

```

I was able to at least hackily work around this by simply casting the times as strings in the constructor like so:

```
class MyFMU(Fmi2Slave):
    ...
    default_experiment = DefaultExperiment(start_time=str(0.), stop_time=str(1.))
    ...
```

But after this it seems the model description validator (when trying to run the fmu through `fmpy` at least) doesn't like the default experiment field being there:
```
---------------------------------------------------------------------------
Exception                                 Traceback (most recent call last)
Cell In [29], line 1
----> 1 simulate_custom_input()

Cell In [28], line 21, in simulate_custom_input(show_plot)
     18 step_size = 1e-3
     20 # read the model description
---> 21 model_description = read_model_description(fmu_filename)
     23 # collect the value references
     24 vrs = {}

File .../lib/python3.8/site-packages/fmpy/model_description.py:415, in read_model_description(filename, validate, validate_variable_names, validate_model_structure)
    413         for entry in schema.error_log:
    414             message += "\n%s (line %d, column %d): %s" % (entry.level_name, entry.line, entry.column, entry.message)
--> 415         raise Exception(message)
    417 modelDescription = ModelDescription()
    418 _copy_attributes(root, modelDescription, ['fmiVersion', 'guid', 'modelName', 'description', 'generationTool',
    419                                           'generationDateAndTime', 'variableNamingConvention'])

Exception: Failed to validate modelDescription.xml:
ERROR (line 38, column 0): Element 'DefaultExperiment': This element is not expected.
```

Would this be an xml serialization issue on this end, or a validation issue on `fmpy`'s end?

Thanks!

btw this is a really nice package! :+1:

### Additional contract requirements

- `DefaultExperiment` is importable from `pythonfmu.fmi2slave` and from `pythonfmu`, and `DefaultExperiment(start_time=...)` records the supplied value as its public `start_time` attribute.
- `FmuBuilder.build_FMU(script_file, project_files=[], dest=..., needsExecutionTool="false")` builds an FMU from a slave script and returns the path of the created FMU.
- When a slave declares a `default_experiment` that is a `DefaultExperiment`, the generated FMU's model description contains that default experiment with its `start_time` value preserved, and the model description validates and can be read by `fmpy`.
