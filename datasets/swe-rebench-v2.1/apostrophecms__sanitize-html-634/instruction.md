Image alt attribute with empty string should not be removed
PLEASE NOTE: make sure the bug exists in the latest patch level of the project. For instance, if you are running a 2.x version of Apostrophe, you should use the latest in that major version to confirm the bug.

## To Reproduce

Step by step instructions to reproduce the behavior:

```sh
npm install sanitize-html@2.11.0
```

```js
import sanitizeHtml from 'sanitize-html';

// EXPECT: <img alt="" src="https://example.com/" />
// ACTUAL: <img src="https://example.com/" />
console.log(
  sanitizeHtml('<img alt="" src="https://example.com/" />', {
    allowedAttributes: { img: ['alt', 'src'] },
    allowedTags: ['img']
  })
);

// EXPECT: <img alt="" src="https://example.com/" />
// ACUTAL: <img alt src="https://example.com/" />
console.log(
  sanitizeHtml('<img alt="" src="https://example.com/" />', {
    allowedAttributes: { img: ['alt', 'src'] },
    allowedTags: ['img'],
    nonBooleanAttributes: []
  })
);
```

## Expected behavior

`alt=""` should be left as-is.

## Describe the bug

Empty `alt` attribute means the alt text of the image is intentionally left blank. For example, border graphics may not need `alt` attribute if they are unimportant decoration.

When `alt` is an empty string, screen reader will skip the element and read nothing.

When `alt` is not set, screen reader will read "image".

So, `alt=""` is not same as `alt` or unset.

To workaround the issue, use `<img role="presentation" src="https://example.com/" />`.

## Details

**Version of Node.js:** 18.16.0
*PLEASE NOTE: Only stable LTS versions (10.x and 12.x) are fully supported but we will do our best with newer versions.*

**Server Operating System:** Ubuntu 20.04 on WSL
*The server (which might be your dev laptop) on which Apostrophe is running. Linux? MacOS X? Windows? Is Docker involved?*

**Additional context:** Seems regression of #529.
> Add any other context about the problem here. If the problem is specific to a browser, OS or mobile device, specify which.

**Screenshots**
*If applicable, add screenshots to help explain your problem.*

```sh
$ cat index.mjs
import sanitizeHtml from 'sanitize-html';

// EXPECT: <img alt="" src="https://example.com/" />
// ACTUAL: <img src="https://example.com/" />
console.log(
  sanitizeHtml('<img alt="" src="https://example.com/" />', {
    allowedAttributes: { img: ['alt', 'src'] },
    allowedTags: ['img']
  })
);

// EXPECT: <img alt="" src="https://example.com/" />
// ACUTAL: <img alt src="https://example.com/" />
console.log(
  sanitizeHtml('<img alt="" src="https://example.com/" />', {
    allowedAttributes: { img: ['alt', 'src'] },
    allowedTags: ['img'],
    nonBooleanAttributes: []
  })
);
$ node ./index.mjs
<img src="https://example.com/" />
<img alt src="https://example.com/" />
```
