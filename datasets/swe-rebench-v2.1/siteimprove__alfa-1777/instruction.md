`isVisible` reports content of closed `<details>`  as visible
The [isVisible](https://github.com/Siteimprove/alfa/blob/ee0c470dab051834d0024ba3868b9c7806a24193/packages/alfa-style/src/node/predicate/is-visible.ts#L29) predicate does not detect content inside a closed `<details>` element as invisible.

Minimal reproducible example:
```
<!doctype html>
<html>
  <head>
    <title>Details Visibility MRE</title>
  </head>
  <body>
    <details>
      <summary>Minimal Reproducible Example</summary>
      <div>I'm invisible</div>
    </details>
  </body>
</html>
```

Comparing with browser dev tools, the `<div>` element has computed styles `visibility: visible` and `display: block` so it's unclear what exactly is the mechanism that makes the element not visible/not rendered.

`<details>` is not added to [user-agent.ts](https://github.com/Siteimprove/alfa/blob/ee0c470dab051834d0024ba3868b9c7806a24193/packages/alfa-cascade/src/user-agent.ts#L4) according to [rendering.html](https://html.spec.whatwg.org/multipage/rendering.html#the-details-and-summary-elements), but it's unclear if adding that will be enough to correctly detect the visibility of the content.

Do we need to add special handling of `<details>` elements in the predicate?

Relates to [II-8780](https://siteimprove-wgs.atlassian.net/browse/II-8780).

[MDN](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/details).

[II-8780]: https://siteimprove-wgs.atlassian.net/browse/II-8780?atlOrigin=eyJpIjoiNWRkNTljNzYxNjVmNDY3MDlhMDU5Y2ZhYzA5YTRkZjUiLCJwIjoiZ2l0aHViLWNvbS1KU1cifQ
