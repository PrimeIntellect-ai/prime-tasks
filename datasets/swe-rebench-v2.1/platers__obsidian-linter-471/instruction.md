Bug: No Bare URLs Breakages in Code Block and Smart Typography
## Describe the Bug

The No Bare URLs rule produces a few unexpected results.

1. When using the Smart Typography extension, quoted URLs get converted. E.g.,

    - `‘https://google.com’` → `‘<https://google.com’>`
    - `“https://google.com”` → `“<https://google.com”>`

2. URLs within backticks containing text other than just the URL. E.g.,

    - `` `http --headers --follow --all https://google.com` ``  → `` `http --headers --follow --all <https://google.com>` ``

![2022-11-02_01](https://user-images.githubusercontent.com/176/199514303-1ea01bb5-d761-4fb1-ac90-a26ec4768c7d.png)

![2022-11-02_02](https://user-images.githubusercontent.com/176/199514349-38a3120e-47eb-4d3c-bdd2-ca686ffe01c9.png)

## How to Reproduce

1. Install Smart Typography extension and use linter on text with curly quotes and No Bare URLs turned on.

2. Has nothing to do with Smart Typography - just run the linter on a backticked string containing a some text + a url.

## Device

- [x] Desktop

Mobile not tested
