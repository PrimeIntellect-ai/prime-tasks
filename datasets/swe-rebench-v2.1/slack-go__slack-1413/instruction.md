Please Add parse function for InteractionCallback
[HIDDEN]

https://github.com/nlopes/slack/blob/8fe460f3467836471f96e0bdfc9689de165f1ee5/examples/buttons/buttons.go#L45-L46

This is a bit confusing and may cause users to change their code when slack API changes.

So, could you add parse function for InteractionCallback `func(*http.Request) (InteractionCallback, error)` like `SlashCommandParse`?

https://github.com/nlopes/slack/blob/0afac90b917f77d7c59d638420d5d40fe65eee61/slash.go#L25

### Additional contract requirements

- Expose the parser under the public name `InteractionCallbackParse`.
- Parse the `payload` form field from the request as an `InteractionCallback`.
- Return an error when the `payload` form value is absent or its contents cannot be parsed as an `InteractionCallback`.
