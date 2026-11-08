Container component for App Home surface
Today Slack introduced "App Home", the new Block Kit surface for the interaction between Slack app and user.
https://api.slack.com/reference/app-home

An usage of Block Kit for App Home is not so different from message. User still can compose contents for App Home by using jsx-slack's `<Blocks>` container.

So why should we create container component? Now [the official document of layout blocks](https://api.slack.com/reference/block-kit/blocks) are sorted to show the supported blocks in each surfaces. Providing `<Home>` container component, with check valid blocks strictly (like #64), is better for composing correct blocks suitable with each view.
