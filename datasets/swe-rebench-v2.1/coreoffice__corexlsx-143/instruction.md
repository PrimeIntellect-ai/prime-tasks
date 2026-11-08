Cannot initialize SchemaType from invalid String value http://customschemas.google.com/relationships/workbookmetadata
**Version**

0.13.0

**Description of the bug**

Probably related to https://github.com/CoreOffice/CoreXLSX/issues/87. [HIDDEN]

### Additional contract requirements

The relationship type URI `http://customschemas.google.com/relationships/workbookmetadata` must be accepted as a valid `SchemaType` value when a relationship containing it is decoded.
