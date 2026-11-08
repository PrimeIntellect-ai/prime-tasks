Error when spaces included in a 'name' property under paths/parameters
When spaces are included in the value for `name under `parameters` this error is thrown:
```
Error: The $ref targets root is not found: #/paths/findPets/parameters/tags%20to%20filter%20by
    at ReferenceResolver.<anonymous> (/Users/_/.npm/_npx/93424/lib/node_modules/dtsgenerator/dist/core/referenceResolver.js:106:35)
    at step (/Users/_/.npm/_npx/93424/lib/node_modules/dtsgenerator/node_modules/tslib/tslib.js:139:27)
    at Object.next (/Users/_/.npm/_npx/93424/lib/node_modules/dtsgenerator/node_modules/tslib/tslib.js:120:57)
    at /Users/_/.npm/_npx/93424/lib/node_modules/dtsgenerator/node_modules/tslib/tslib.js:113:75
    at new Promise (<anonymous>)
    at Object.__awaiter (/Users/_/.npm/_npx/93424/lib/node_modules/dtsgenerator/node_modules/tslib/tslib.js:109:16)
    at ReferenceResolver.resolve (/Users/_/.npm/_npx/93424/lib/node_modules/dtsgenerator/dist/core/referenceResolver.js:26:24)
    at DtsGenerator.<anonymous> (/Users/_/.npm/_npx/93424/lib/node_modules/dtsgenerator/dist/core/dtsGenerator.js:22:50)
    at step (/Users/_/.npm/_npx/93424/lib/node_modules/dtsgenerator/node_modules/tslib/tslib.js:139:27)
    at Object.next (/Users/_/.npm/_npx/93424/lib/node_modules/dtsgenerator/node_modules/tslib/tslib.js:120:57)
```
For example:
```
paths:
  /pets:
    get:
      description: Returns all pets from the system that the user has access to
      operationId: findPets
      parameters:
        - name: tags to filter by
          in: query
          description: tags to filter by
          required: false
          style: form
          schema:
            type: array
            items:
              type: string
```

I've attached the full example schema file which causes this error
[pet-expanded.txt](https://github.com/horiuchi/dtsgenerator/files/4531306/pet-expanded.txt)

### Additional contract requirements

- The module `src/core` default-exports an async function `dtsgenerator(options)`. It accepts `options.contents`, an array of schema objects, and returns a `Promise<string>` containing the generated TypeScript declaration code.
