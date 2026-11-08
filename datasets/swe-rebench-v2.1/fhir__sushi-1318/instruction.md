Warning messages about unrecognized configuration properties under "pages" always suggest file type endings
https://chat.fhir.org/#narrow/stream/215610-shorthand/topic/error.20message/near/376451856

```yaml
pages:
  deployment.md:
    Title: Deployment
```
The `title` property should be lowercase, so a warning is emitted. But, since the property path starts with `/pages`, SUSHI emits the warning message `Pages should end with .md, .xml, or .html.`. The property path will need to be checked more carefully to see if that warning message is appropriate.

### Additional contract requirements

- For an unrecognized configuration property, the warning includes `Configuration contains unexpected property: cookie. Check that this property is spelled, capitalized, and indented correctly.` for the `cookie` case.
- For multiple unrecognized configuration properties, the warning includes `Configuration contains unexpected properties: cookie, index.md. Check that these properties are spelled, capitalized, and indented correctly.` for the `cookie, index.md` case.
- For an unrecognized property under `pages`, the warning includes `Configuration property pages contains unexpected property: menu. Check that this property is spelled, capitalized, and indented correctly. If this is a page, it should end with .md, .xml, or .html.` for the `menu` case.
- For multiple unrecognized properties under `pages`, the warning includes `Configuration property pages contains unexpected properties: menu, license. Check that these properties are spelled, capitalized, and indented correctly. If these are pages, they should end with .md, .xml, or .html.` for the `menu, license` case.
- For an unrecognized property inside a page configuration, such as `Title` inside `deployment.md`, the warning names the full property path and includes `Configuration property pages/deployment.md contains unexpected property: Title. Check that this property is spelled, capitalized, and indented correctly. If this is a page, it should end with .md, .xml, or .html.`
