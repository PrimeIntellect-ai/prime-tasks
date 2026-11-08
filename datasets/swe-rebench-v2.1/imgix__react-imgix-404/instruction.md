Use sizes on <Source> to generate srcSet
**Before you submit:**

- [x] Please search through the existing issues (both open AND closed) to see if your issue has been discussed before. Github issue search can be used for this: https://github.com/imgix/react-imgix/issues?utf8=%E2%9C%93&q=is%3Aissue
- [x] Please ensure the problem has been isolated and reduced. This link explains more: http://css-tricks.com/6263-reduced-test-cases/

**Describe the bug**

It looks like the `<Source>` component ignores the `sizes=` attribute and just generates a `srcSet` with different resolutions. [HIDDEN]
But I _think_ `<source>` should be able to support fluid width images the same as `<img>`? Is there a reason that `<Source>` components are grouped in with fixed size images?

**To Reproduce**
```
<Picture>
  <Source
    src={desktopSrc}
    sizes="100vw"
    htmlAttributes={{ media: "(min-width: 768px)" }}
  />
  <Source
    src={mobileSrc}
    sizes="100vw"
    htmlAttributes={{ media: "(min-width: 320px)" }}
  />
  <Imgix src={mobileSrc} sizes="100vw" />
</Picture>
```

**Expected behaviour**

I'd expect a `<Source>` to generate its `srcSet` based on `sizes=` similar to the `<Imgix>` component - otherwise art-directed images end up much larger than they need to be.

### Additional contract requirements

- A fluid `<Source>` must produce a responsive, width-descriptor `srcSet` so the browser can select an appropriate candidate using its `sizes` value, analogous to `<Imgix>`.
