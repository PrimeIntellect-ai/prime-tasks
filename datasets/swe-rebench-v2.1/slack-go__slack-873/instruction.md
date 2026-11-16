[BUG]Button default style is wrong
Due to the introduction for slack button, default style should be omitted.
And there will be an invalid block error when set to default.

```
{
	"blocks": [
		{
			"type": "actions",
			"block_id": "actionblock789",
			"elements": [
				{
					"type": "button",
					"text": {
						"type": "plain_text",
						"text": "Primary Button"
					},
should be deleted --->			"style": "default",
					"value": "click_me_456"
				}
			]
		}
	]
}
```

code is here, [HIDDEN]
https://github.com/slack-go/slack/blob/e96a24877c12e04ce3692a3096559b2ccfbeb26d/block_element.go#L133
