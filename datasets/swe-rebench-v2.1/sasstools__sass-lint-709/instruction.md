no-vendor-prefixes : Throws error on Non-Standard Rule
When enforcing the [no-vendor-prefixes](https://github.com/sasstools/sass-lint/blob/master/docs/rules/no-vendor-prefixes.md) rule, it throws errors due to non-standard rules, as utilized in [normalize.css](https://necolas.github.io/normalize.css/4.1.1/normalize.css):

/* Remove inner padding and border in Firefox 4+.*/
`button::-moz-focus-inner,
input::-moz-focus-inner {
    border: 0;
    padding: 0;
}`

/* Fix the cursor style for Chrome's increment/decrement buttons. For certain font-size values of the input, it causes the cursor style of the decrement button to change from default` to text.*/

`input[type="number"]::-webkit-inner-spin-button,
input[type="number"]::-webkit-outer-spin-button {
    height: auto;
}`

> error  Vendor prefixes should not be used  no-vendor-prefixes

Yes, this is a vendor prefix, but it is for a non-standard rule, and is targeting Specific Browser Sudo Elements

I'm tempted to exclude our normalize.scss file from linting, but I would prefer not to.

Could there be an option, added to the rule, that would allow the user to list non-standard css rules that would then be ignored by the linter?

What version of Sass Lint are you using?
"gulp-sass": "2.0.4"
"gulp-sass-lint": "1.7.0"

### Additional contract requirements

- Users can select vendor identifiers to exempt with the rule's `excluded-identifiers` array (for example, `webkit` or `moz`); this list is distinct from `ignore-non-standard` and applies regardless of whether the affected prefixed property or element is standard.
- The `no-vendor-prefixes` rule must accept the `ignore-non-standard` option; when set to `true`, it ignores non-standard prefixed properties and elements.
