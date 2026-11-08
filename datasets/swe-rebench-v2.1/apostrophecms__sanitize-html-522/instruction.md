allow '!important' for style attributes
Hey everyone,

I am currently trying to allow the important flag for CSS Attribute inside the style attribute for tags. I did not manage to get it work, the sanitizer always removes the '!important'.

Here is a code sandbox: https://codesandbox.io/s/wizardly-agnesi-64lc2?file=/src/index.js

I tried to use allowStyles but could not figure out the right config, the docs do not mention this specific case.

Looking forward to your answers!

Max


## Details

**Version of Node.js:**
14 LTS

**Server Operating System:**
Linux

### Additional contract requirements

- With `allowedTags: false`, `allowedAttributes: { span: ['style'] }`, and `allowedStyles: { span: { color: [/blue/] } }`, sanitizing `<span style='color: blue !important'></span>` must return exactly `<span style="color:blue !important"></span>`.
