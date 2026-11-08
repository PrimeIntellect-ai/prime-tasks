Report link info from the Package Document
It would be useful (but hardly critical) to get a list of links along with the metadata, pairing rel to href.

The reason I ask is that conformance to the a11y spec is done through a link, so I can't pick up if the metadata is already set in the publication:

```
<link rel="dcterms:conformsTo" href="http://www.idpf.org/epub/a11y/accessibility-20170105.html#wcag-aa"/>
```

The same is also true for the certifierReport link and potentially also the certifierCredential.

It's not going to be common, but I can see two scenarios where this metadata might be present: 1) someone sets the metadata prematurely/automatically, and 2) someone needs to reverify a publication.

Without access to the link info, I can't reset these fields in the verification tool.

### Additional contract requirements

- The generated report's test subject (`earl:testSubject`) includes a `links` property with the link elements of the EPUB's Package Document, mapping each link relation (`rel`) to its `href`. For example, a Package Document containing `<link rel="a11y:certifierReport" href="http://www.example.com/report.html"/>` produces `"links": { "a11y:certifierReport": "http://www.example.com/report.html" }`.
