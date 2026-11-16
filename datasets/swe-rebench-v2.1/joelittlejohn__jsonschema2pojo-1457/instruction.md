Fix questionable error message for the application of a source file name filter
I am trying the current software release out.

```
Markus_Elfring@…:~/Downloads/Freeware/jsonschema2pojo-1.1.2/bin> sh jsonschema2pojo -s ~/Test/JSON/Schemas/*Schema1.json -t ~/Bau/JSON/Schemas
Was passed main parameter '/home/Markus_Elfring/Test/JSON/Schemas/Staffelstufe-reduced-Schema1.json' but no main parameter was defined
Usage: jsonschema2pojo [options]
…
  * -s, --source
       The source file(s) or directory(ies) from which JSON Schema will be read
…
```

How does the shown error message fit to the applied source file name filter according to the presented help information? :thinking:

:crystal_ball: Can affected implementation details be improved further?

### Additional contract requirements

When `-s` or `--source` is followed by multiple source paths in one command-line invocation, each path must be treated as a source. This includes multiple filenames supplied by shell expansion; later paths must not be rejected as undefined positional parameters.
