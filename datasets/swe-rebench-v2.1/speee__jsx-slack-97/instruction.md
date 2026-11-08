Allow `verbatim={boolean}` parameter
For text objects, Slack allows a parameter `verbatim` to be passed, allowing some elements to be parsed by slack, without needing specific mrkdwn syntax (e.g. channels, users, urls). From Slack's doc on text object: https://api.slack.com/reference/block-kit/composition-objects#text


When set to false (as is default) URLs will be auto-converted into links, conversation names will be link-ified, and certain mentions will be automatically parsed. Using a value of true will skip any preprocessing of this nature, although you can still include manual parsing strings. This field is only usable when typeis mrkdwn.


It would be ideal to be able to use this attribute for components that support a text object (e.g. Section, Context, Fields (and pass them down to child elements). A specific use case where this would be ideal is rendering dynamic input in slack. If the dynamic content contains a URL, passing the text into a `jsx-slack` component such as a `<Button>` means you would first have to search for url's and wrap them with `<a>...</a>` to get them to render as links in Slack. Ideally you could opt into the `verbatim` parameter to simply pass the raw text to Slack to parse

### Additional contract requirements

- Add a public `Mrkdwn` component, exported from the package's main entry point (the same module that exports `Section`, `Context`, and `Confirm`). It accepts JSX children and an optional `verbatim` boolean prop.
- `<Mrkdwn>` converts its children to mrkdwn text. When used inside a `<Section>`, it becomes the section's `text` as an mrkdwn text element of the form `{ type: 'mrkdwn', text, verbatim }`, preserving the supplied `verbatim` value.
- When used inside a `<Context>`, `<Mrkdwn>` becomes an mrkdwn element within the context's `elements`, preserving its text and `verbatim` value.
- Ordinary (non-`<Mrkdwn>`) text children of `<Context>` continue to be emitted as mrkdwn elements with `verbatim: true`.
- When used inside a `<Confirm>`, `<Mrkdwn>` becomes the confirmation's `text` as an mrkdwn text element of the form `{ type: 'mrkdwn', text, verbatim }`, preserving its text and `verbatim` value.
- Fields are an aspirational example in the original request, not a required integration for this change. `<Mrkdwn>` is not required to be accepted inside `<Field>` or to let a Field caller override its existing `verbatim` behavior.
