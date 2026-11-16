No domContentLoaded event in trace
I'm using lighthouse for automatic page test, and I've encountered this warning, which makes the performance score very slow, could anyone help to figure out why is this happening?

```
~/dev/node-test/chrome lighthouse https://h5.m.taobao.com/trip/home/index.html
  ChromeLauncher Waiting for browser. +0ms
  ChromeLauncher Waiting for browser... +1ms
  ChromeLauncher Waiting for browser..... +515ms
  ChromeLauncher Waiting for browser.....✓ +4ms
  status Initializing… +770ms
  status Loading page & waiting for onload URL, Viewport, ViewportDimensions, ThemeColor, Manifest, ChromeConsoleMessages, ImageUsage, Accessibility, EventListeners, AnchorsWithNoRelNoopener, AppCacheManifest, DOMStats, JSLibraries, OptimizedImages, PasswordInputsWithPreventedPaste, ResponseCompression, TagsBlockingFirstPaint, WebSQL +346ms
  statusEnd Loading page & waiting for onload +14s
  status Retrieving trace +1ms
  status Retrieving devtoolsLog and network records +2s
  status Retrieving: URL +14ms
  status Retrieving: Viewport +1ms
  status Retrieving: ViewportDimensions +5ms
  status Retrieving: ThemeColor +6ms
  status Retrieving: Manifest +2ms
  status Retrieving: ChromeConsoleMessages +1ms
  status Retrieving: ImageUsage +2ms
  status Retrieving: Accessibility +59ms
  status Retrieving: EventListeners +262ms
  status Retrieving: AnchorsWithNoRelNoopener +230ms
  status Retrieving: AppCacheManifest +2ms
  status Retrieving: DOMStats +3ms
  status Retrieving: JSLibraries +15ms
  status Retrieving: OptimizedImages +9ms
  status Retrieving: PasswordInputsWithPreventedPaste +161ms
  status Retrieving: ResponseCompression +2ms
  status Retrieving: TagsBlockingFirstPaint +6ms
  status Retrieving: WebSQL +4ms
  status Loading page & waiting for onload ServiceWorker, Offline, StartUrl +811ms
  statusEnd Loading page & waiting for onload +230ms
  status Retrieving devtoolsLog and network records +47ms
  status Retrieving: ServiceWorker +7ms
  status Retrieving: Offline +0ms
  status Retrieving: StartUrl +34ms
  status Loading page & waiting for onload HTTPRedirect, HTMLWithoutJavaScript +333ms
  statusEnd Loading page & waiting for onload +179ms
  status Retrieving devtoolsLog and network records +0ms
  status Retrieving: HTTPRedirect +6ms
  status Retrieving: HTMLWithoutJavaScript +7ms
  status Disconnecting from browser... +5ms
  status Analyzing and running audits... +30ms
  status Evaluating: Uses HTTPS +0ms
  status Evaluating: Redirects HTTP traffic to HTTPS +8ms
  status Evaluating: Registers a service worker +1ms
  status Evaluating: Responds with a 200 when offline +0ms
  status Evaluating: Has a `<meta name="viewport">` tag with `width` or `initial-scale` +1ms
  status Evaluating: Contains some content when JavaScript is not available +2ms
  status Evaluating: First meaningful paint +1ms
  status Evaluating: Page load is fast enough on 3G +125ms
  load-fast-enough-for-pwa:warn Caught exception: No domContentLoaded event in trace +34ms
  status Evaluating: Perceptual Speed Index +0ms
  status Evaluating: Screenshot Thumbnails +2s
  status Evaluating: Estimated Input Latency +187ms
  status Evaluating: No browser errors logged to the console +5ms
  status Evaluating: Keep server response times low (TTFB) +1ms
  status Evaluating: First Interactive (beta) +1ms
  first-interactive:warn Caught exception: No domContentLoaded event in trace +0ms
  status Evaluating: Consistently Interactive (beta) +0ms
  consistently-interactive:warn Caught exception: No domContentLoaded found in trace. +0ms
  status Evaluating: User Timing marks and measures +0ms
  status Evaluating: Critical Request Chains +11ms
  status Evaluating: User can be prompted to Install the Web App +3ms
  status Evaluating: Configured for a custom splash screen +1ms
  status Evaluating: Address bar matches brand colors +0ms
  status Evaluating: Manifest's `short_name` won't be truncated when displayed on homescreen +0ms
  status Evaluating: Content is sized correctly for the viewport +1ms
  status Evaluating: Uses Images with appropriate aspect ratio +0ms
  status Evaluating: Avoids deprecated APIs +2ms
  status Evaluating: Site works cross-browser +0ms
  status Evaluating: Page transitions don't feel like they block on the network +0ms
  status Evaluating: Each page has a URL +0ms
  status Evaluating: `[accesskey]` values are unique. +0ms
  status Evaluating: `[aria-*]` attributes match their roles. +1ms
  status Evaluating: `[role]`s have all required `[aria-*]` attributes. +0ms
  status Evaluating: Elements with `[role]` that require specific children `[role]`s, are present. +0ms
  status Evaluating: `[role]`s are contained by their required parent element. +0ms
  status Evaluating: `[role]` values are valid. +0ms
  status Evaluating: `[aria-*]` attributes have valid values. +0ms
  status Evaluating: `[aria-*]` attributes are valid and not misspelled. +0ms
  status Evaluating: `<audio>` elements contain a `<track>` element with `[kind="captions"]`. +0ms
  status Evaluating: Buttons have an accessible name. +0ms
  status Evaluating: The page contains a heading, skip link, or landmark region. +1ms
  status Evaluating: Background and foreground colors have a sufficient contrast ratio. +0ms
  status Evaluating: `<dl>`'s contain only properly-ordered `<dt>` and `<dd>` groups, `<script>` or `<template>` elements. +0ms
  status Evaluating: Definition list items are wrapped in `<dl>` elements. +0ms
  status Evaluating: Document has a `<title>` element. +0ms
  status Evaluating: `[id]` attributes on the page are unique. +0ms
  status Evaluating: `<frame>` or `<iframe>` elements have a title. +0ms
  status Evaluating: `<html>` element has a `[lang]` attribute. +0ms
  status Evaluating: `<html>` element has a valid value for its `[lang]` attribute. +0ms
  status Evaluating: Image elements have `[alt]` attributes. +0ms
  status Evaluating: `<input type="image">` elements have `[alt]` text. +1ms
  status Evaluating: Form elements have associated labels. +0ms
  status Evaluating: Presentational `<table>` elements avoid using `<th>`, `<caption>` or the `[summary]` attribute. +0ms
  status Evaluating: Links have a discernible name. +0ms
  status Evaluating: Lists contain only `<li>` elements and script supporting elements (`<script>` and `<template>`). +0ms
  status Evaluating: List items (`<li>`) are contained within `<ul>` or `<ol>` parent elements. +0ms
  status Evaluating: The document does not use `<meta http-equiv="refresh">`. +0ms
  status Evaluating: `[user-scalable="no"]` is not used in the `<meta name="viewport">` element and the `[maximum-scale]` attribute is not less than 5. +1ms
  status Evaluating: `<object>` elements have `[alt]` text. +0ms
  status Evaluating: No element has a `[tabindex]` value greater than 0. +0ms
  status Evaluating: Cells in a `<table>` element that use the `[headers]` attribute only refer to other cells of that same table. +0ms
  status Evaluating: `<th>` elements and elements with `[role="columnheader"/"rowheader"]` have data cells they describe. +0ms
  status Evaluating: `[lang]` attributes have a valid value. +0ms
  status Evaluating: `<video>` elements contain a `<track>` element with `[kind="captions"]`. +0ms
  status Evaluating: `<video>` elements contain a `<track>` element with `[kind="description"]`. +0ms
  status Evaluating: Avoids enormous network payloads +0ms
  status Evaluating: Offscreen images +7ms
  offscreen-images:warn Caught exception: No domContentLoaded event in trace +24ms
  status Evaluating: Serve images as WebP +0ms
  status Evaluating: Optimize images +1ms
  status Evaluating: Enable text compression +1ms
  status Evaluating: Properly size images +0ms
  status Evaluating: Avoids Application Cache +17ms
  status Evaluating: Avoids an excessive DOM size +0ms
  status Evaluating: Opens external anchors using `rel="noopener"` +2ms
  status Evaluating: Avoids requesting the geolocation permission on page load +0ms
  status Evaluating: Reduce render-blocking stylesheets +1ms
  status Evaluating: Avoids `document.write()` +0ms
  status Evaluating: Avoids Mutation Events in its own scripts +1ms
  status Evaluating: Avoids front-end JavaScript libraries with known security vulnerabilities +71ms
  status Evaluating: Avoids WebSQL DB +0ms
  status Evaluating: Avoids requesting the notification permission on page load +1ms
  status Evaluating: Allows users to paste into password fields +0ms
  status Evaluating: Reduce render-blocking scripts +0ms
  status Evaluating: Uses HTTP/2 for its own resources +0ms
  status Evaluating: Uses passive listeners to improve scrolling performance +2ms
  status Generating results... +1ms
  Printer domhtml output written to /Users/dickeylth/dev/node-test/chrome/h5.m.taobao.com_2017-11-17_17-15-36.report.html +20ms
  CLI Protip: Run lighthouse with `--view` to immediately open the HTML report in your browser +0ms
  ChromeLauncher Killing Chrome instance 93287 +1ms
```

You could see there's

```
  load-fast-enough-for-pwa:warn Caught exception: No domContentLoaded event in trace +34ms
  first-interactive:warn Caught exception: No domContentLoaded event in trace +0ms
  consistently-interactive:warn Caught exception: No domContentLoaded found in trace. +0ms
  offscreen-images:warn Caught exception: No domContentLoaded event in trace +24ms
```

and the score is really slow:

<img width="839" alt="2017-11-17_17-18-25" src="https://user-images.githubusercontent.com/2196373/32939741-7a2823b0-cbbb-11e7-9e99-2a7115e35879.png">


which could not reflect the real performance in my opinion.

Looking forward to any help! Thank you.

### Additional contract requirements

When a trace contains a navigation start for an unrelated non-web target alongside the page navigation, Lighthouse must use the relevant page navigation. As a result, audits that rely on page-navigation timing data can find DOMContentLoaded and report meaningful performance results instead of failing because an unrelated navigation was selected.
