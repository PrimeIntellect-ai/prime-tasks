Unable to use a spectral file located in Enterprise Github with a token parameter
**Describe the bug**
When trying to use a spectral lint file that requires a token param, Spectral throws an unexpected error

```
Error running Spectral!
Error #1: Unexpected token (Note that you need plugins to import files that are not JavaScript)
          at error            …hared/rollup.js:198  base = Object.assig…
          at error            …red/rollup.js:12555  return error(props);
          at tryParse         …red/rollup.js:12932  return this.error({
          at setSource        …red/rollup.js:12837  ast = this.tryParse…
          at addModuleSource  …red/rollup.js:22311  module.setSource(aw…
```

**To Reproduce**

1. Create a GitHub repository and place a spectral file there, like this:
    * style.yaml
```
extends: spectral:oas
rules:
  oas3-api-costcenter:
    description: There must be x-cost-center.
    given: $
    severity: error
    then:
      field: x-cost-center
      function: truthy

  oas3-api-businessid:
    description: There must be x-business-id.
    given: $
    severity: error
    then:
      field: x-business-id
      function: truthy
```
2. Go to the raw view of that spectral file and copy the url, it should have a token in it
2. Create a local folder with a "src" folder and a basic api-schema.json file that has an oas schema
3. Run this CLI command 'spectral lint "./src/api-schema.json" --ruleset {url with token from step 2} --verbose'
4. See error
```
Error running Spectral!
Error #1: Unexpected token (Note that you need plugins to import files that are not JavaScript)
          at error            …hared/rollup.js:198  base = Object.assig…
          at error            …red/rollup.js:12555  return error(props);
          at tryParse         …red/rollup.js:12932  return this.error({
          at setSource        …red/rollup.js:12837  ast = this.tryParse…
          at addModuleSource  …red/rollup.js:22311  module.setSource(aw…
```

**Expected behavior**
I would expect that Spectral would be able to ingest this file as a standard curl command shows the file as it should be.  Additionally, if I pull the file down locally and put it in the repo, it runs fine.

**Environment (remove any that are not applicable):**
 - Library version: Spectral v6.5.1
 - OS: Windows 10
 - Browser: n/a

**Additional context**
Add any other context about the problem here.
