Incorrect elision of named import if typings of a callback function contains a parameter with the same name
I came across a bit of an odd bug while using Sucrase.

In the following code, notice that `someVariable` is used as an import name but also used in the type definition of the argument of the function.
```typescript
import { someVariable } from './someFile';

function Foo(arg: (someVariable: any) => void) {
  console.log(arg, someVariable);
}
```

Somehow, in the generated code by Sucrase, the import is lost while it should have been kept
```javascript
function Foo(arg) {
  console.log(arg, someVariable);
}
```

Renaming the import or the parameter name of the callback type will fix the issue


Playground link https://sucrase.io/#transforms=jsx%2Ctypescript&enableLegacyTypeScriptModuleInterop=true&enableLegacyBabel5ModuleInterop=true&compareWithTypeScript=true&compressedCode=H4sIAKqarmQAA12Psc7CMBCD9zyFxQKVEN1BPyNPgNiv4egfcclVlwCqEO9OihiA1bI%2F22hblP%2BQEeKgVnALIugYxlGvfEQ3Il%2B8UWb3dtyRNfKBLFAnjAdOphHzVTvJuyA83zhXqXsbUbSCEkWuHQxPIh35MwayqhU2zD5Zs8lPaax7Ug%2BWzMtX7mfamYfiTpfkS9CEneqCrF9j8YlaT5wGf1tcNRwb3B3gNWUVXon2U2L59aPZuMcTOupspAwBAAA%3D
