Add Current Node Index in `replace` Callback
## Problem
I'm working with `HTML/JS` code fetched from a CMS. This code may contain multiple scripts. I'm using `next/script` which requires each script to have a unique id. However, when there are many scripts, it's challenging to assign the correct id since the scripts are dynamically mounted.

Here's how I'm currently handling scripts:

```ts
parser(html, {
  replace(domNode) {
    if (domNode instanceof Element && domNode.type === "script") {
      const __html = domNode.children
        .filter((child) => child instanceof Text)
        .map((child) => (child as Text).data)
        .join("");

      const props = attributesToProps(domNode.attribs);

      return (
        <Script
          {...props}
          dangerouslySetInnerHTML={{
            __html
          }}
        />
      );
    }
  }
});
```

I could assign a unique id to each script, but this would require handling many cases and tracking which script has the current id and which script is currently mounting to avoid id duplication.

so I’ve come up with this solution:
```ts
import React from "react";

import Script from "next/script";

import parser, { Element, Text, attributesToProps, htmlToDOM } from "html-react-parser";

function parseHTML(html: string | null | undefined, fixedID: string) {
  //get all script tags and map them to an array with their index
  const scripts = new Set(
    html
      ? htmlToDOM(html)
          .filter((node) => node instanceof Element && node.type === "script")
          .map((_, index) => index)
      : []
  );

  return (
    html &&
    parser(html, {
      replace(domNode) {
        if (domNode instanceof Element && domNode.type === "script") {
          const __html = domNode.children
            .filter((child) => child instanceof Text)
            .map((child) => (child as Text).data)
            .join("");

          const props = attributesToProps(domNode.attribs);

          //get the first script tag and remove it from the set
          const id = `script-${scripts.values().next().value}`;
          scripts.delete(Number(id.replace("script-", "")));

          return (
            <Script
              {...props}
              id={`${fixedID}-${id}`}
              dangerouslySetInnerHTML={{
                __html
              }}
            />
          );
        }
      }
    })
  );
}

export default parseHTML;
```
I can’t use `useMemo` in scripts because it’s not in a React component or a hook. So, each time a re-render happens, the scripts will be recalculated. Also, I think that looping through the DOM to filter only the script tags and map them into an index may cause performance issues because the `html` may be large or contain many elements, and each time a re-render happens, the code will run again.


## Suggested Solution
the best solution is adding the current node index as a parameter in `replace` callback. so I can easily have a unique id and have smth like: `const cacheKey = ${fixedID}-${index}`.

## Keywords

`next/script`, dynamic script handling, unique id, replace.

### Additional contract requirements

- The `replace` callback receives the current node’s index as its second argument. The index is zero-based within that node’s sibling list and resets to `0` for each child list.
- TypeScript callers can declare and use the callback’s second parameter as a number.
