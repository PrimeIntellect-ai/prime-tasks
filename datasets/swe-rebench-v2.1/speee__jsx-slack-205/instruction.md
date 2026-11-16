Support for Dispatch Action Config for Plain Text Input
As seen here: https://api.slack.com/reference/block-kit/block-elements#input

### Additional contract requirements

For the plain-text `<Input>` and `<Textarea>` components, `dispatchAction` may be a boolean or may specify one or more trigger names using `onEnterPressed` and `onCharacterEntered`. Multiple names may be supplied as a space-separated string or an array. Boolean values control the input block's `dispatch_action` field. When trigger names are supplied, the rendered Slack input block enables dispatch actions and includes an element `dispatch_action_config` whose `trigger_actions_on` contains the corresponding Slack trigger identifiers (`on_enter_pressed` and/or `on_character_entered`). The order of those identifiers is not significant.
