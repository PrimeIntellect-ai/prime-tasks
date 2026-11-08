Allow `verbatim={boolean}` parameter
For text objects, Slack allows a parameter `verbatim` to be passed, allowing some elements to be parsed by slack, without needing specific mrkdwn syntax (e.g. channels, users, urls). From Slack's doc on text object: https://api.slack.com/reference/block-kit/composition-objects#text


When set to false (as is default) URLs will be auto-converted into links, conversation names will be link-ified, and certain mentions will be automatically parsed. Using a value of true will skip any preprocessing of this nature, although you can still include manual parsing strings. This field is only usable when typeis mrkdwn.


It would be ideal to be able to use this attribute for components that support a text object (e.g. Section, Context, Fields (and pass them down to child elements). A specific use case where this would be ideal is rendering dynamic input in slack. If the dynamic content contains a URL, passing the text into a `jsx-slack` component such as a `<Button>` means you would first have to search for url's and wrap them with `<a>...</a>` to get them to render as links in Slack. Ideally you could opt into the `verbatim` parameter to simply pass the raw text to Slack to parse
