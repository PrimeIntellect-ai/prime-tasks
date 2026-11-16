Update mediaIndicator to handle audio
Waiting for SVG from UX

**Is your feature request related to a problem? Please describe.**
We currently have a [MediaIndicator](https://github.com/bbc/psammead/blob/latest/packages/components/psammead-media-indicator/src/index.jsx) component, however it only supports video assets. We will need to enable it to display a different icon depending on whether it's a video or an audio asset.

Pass `type` prop of 'audio' or 'video' and switch svg on it. We should also vary the off screen text, and translate it, passing in a value from simorgh.

**Describe the solution you'd like**
Display different SVGs for icons depending on media type.

**Testing notes**
[Tester to complete]

Dev insight: Unit tests, storybook
