Support new `singleAttributePerLine` option in Prettier 2.6
### bracketSameLine

false

### printWidth

120

### tabWidth

_No response_

### xmlWhitespaceSensitivity

strict

### xmlSelfClosingSpace

false

### Input XML

```xml
<!-- Can't create a regular issue with the new template, so ~~ab~~using the formatting issue type -->

<xref href="https://github.com/prettier/plugin-xml/issues/2" format="html" scope="external">#2</xref>
```


### Current output XML

```xml
<!-- With "singleAttributePerLine": true in `.prettierrc.json` the output is the same as authored -->

<xref href="https://github.com/prettier/plugin-xml/issues/2" format="html" scope="external">#2</xref>
```


### Expected output XML

```xml
<!-- Print only one attribute per line like in Vue SFC templates, HTML, and JSX -->

<xref
  href="https://github.com/prettier/plugin-xml/issues/2"
  format="html"
  scope="external"
>#2
</xref>
```
