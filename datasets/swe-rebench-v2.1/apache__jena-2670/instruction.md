RDF/XML: The presence of both rdf:parseType and rdf:datatype on a property element should be an error
### Version

5.1.0

### What happened?

Test case:

```
<?xml version="1.0"?>

<rdf:RDF
    xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    xml:base="http://base/"
    xmlns:xsd="http://www.w3.org/2001/XMLSchema#"
    xmlns:ex="http://example/">

  <rdf:Description rdf:about="s">
    <ex:property rdf:parseType="Literal" rdf:datatype="http://www.w3.org/2001/XMLSchema#integer">
      123
    </ex:property>
  </rdf:Description>
</rdf:RDF>
```


### Relevant output and stacktrace

_No response_

### Are you interested in making a pull request?

Yes
