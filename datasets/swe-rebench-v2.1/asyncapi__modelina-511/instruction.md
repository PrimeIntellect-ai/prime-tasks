Java equals and hashcode breaks compilation
When generating a java model including equals and hashcode settings, the resulting files break compilation.

[HIDDEN]

Sample repo: https://github.com/ThanksForAllTheFish/modelinabug

How to reproduce once cloned:

- `npm ci`
- `npm run generate`
- check files in `java/org/t4atf/asyncapi`, equals and hashcode are properly implemented, but the import is missing

Verified against latest modelina npm package (0.39.4)

### Additional contract requirements

- When the Java common preset is enabled, every generated class that includes `equals` or `hashCode` must compile without errors.
