Children Presentational: Trueなロールの内部にある場合、画像に関するチップを表示しない
tagNameやaria-hiddenなどは不要な気がしてきた。

### Additional contract requirements

- `getClosestByRoles(el: Element, roles: KnownRole[])` in `src/content/dom/getClosestByRoles.ts` returns the nearest element, including `el` itself, whose computed role is one of `roles`, or `null` when no such element exists in the ancestry.
- `isPresentationalChildren(el: Element)` in `src/content/dom/isPresentationalChildren.ts` returns `true` when `el` is inside a control whose ARIA role has the Children Presentational property set to true (for example `role="button"`, `role="checkbox"`, `role="tab"`, or a native `<button>` element), and `false` otherwise.
- `imageTips(el: Element)` in `src/content/dom/tips/imageTips.ts` returns the accessibility tips for an image element. For an `<img>` without an `alt` attribute it reports an error whose content is `messages.noAltImage`; for an `<img>` with an empty `alt` attribute it reports a warning whose content is `messages.emptyAltImage`. For an `<svg>` that is not hidden and is not inside a presentational control it reports a warning whose content is `messages.mayBeSkipped`; otherwise it reports no tip for the SVG.

- The missing-`alt` error and empty-`alt` warning apply only when the image is not hidden, does not have a presentation role, and is not inside a presentational control; in those cases, no image tip is reported.
