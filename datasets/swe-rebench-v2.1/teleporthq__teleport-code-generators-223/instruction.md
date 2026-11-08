Component names are not same as specified in UIDL
After this #168, I tried exporting a project from CLI too code sandbox using ``codesandbox cli`` and a sandbox is created here --> https://codesandbox.io/s/8zz2kr8118 and then here is the bug the component name is not the same as that is specified in the UIDL is
~~~
        {
            "value": "contact-us",
            "meta": {
              "path": "/here-we-are",
              "componentName": "Us"
            }
          }
~~~

And the import statement is being generated properly
~~~
import Us from './pages/contact-us'
~~~

But the file name that is being generated is something like this
~~~
contactus.css
contactus.js
~~~

### Additional contract requirements

The shared string utilities module `packages/teleport-generator-shared/src/utils/string-utils.ts` must expose the following public functions:

- `camelCaseToDashCase(str: string): string` — converts camelCase or PascalCase text to lower-case dash-separated text. For example, both `PrimaryButton` and `primaryButton` become `primary-button`. Text that is already dash-case is returned unchanged, and digits are left untouched.
- `dashCaseToUpperCamelCase(str: string): string` — converts text to UpperCamelCase (PascalCase). For example, `primary-button` becomes `PrimaryButton` and `primaryButton` becomes `PrimaryButton`. Leading and trailing dashes are ignored, and text that is already UpperCamelCase is returned unchanged.
- `dashCaseToCamelCase(str: string): string` — converts dash-separated text to camelCase. For example, `primary-button` becomes `primaryButton`. A leading dash causes the following segment to be capitalized, so `-primary-button` becomes `PrimaryButton`, while trailing dashes are ignored. Text that is already camelCase or UpperCamelCase is returned unchanged.

Generated project file names must be the dash-case form of the component name: a component named `OneComponent` must be written to a file named `one-component`.
