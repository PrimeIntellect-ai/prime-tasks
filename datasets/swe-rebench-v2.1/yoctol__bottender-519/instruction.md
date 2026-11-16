Slack interactive events payload isn't parsed correctly
**Describe the bug**

Slack interaction events send back a nested payload, which causes error for event parsing and further handling.
```
{
  "paylaod": "{
    // real payload JSON
  }"
}
```

**To Reproduce**
Steps to reproduce the behavior:
1. set webhook URL for Slack event subscription
![image](https://user-images.githubusercontent.com/4010549/68449255-6af77500-0221-11ea-8b0a-e76fdc32501e.png)

2. set webhook URL for Slack interaction events
![image](https://user-images.githubusercontent.com/4010549/68449221-413e4e00-0221-11ea-8fc6-93c3e44279b1.png)

3. send a Slack block components message to you slack channel (with buttons or other action components)
e.g.
```
{
	"blocks": [
		{
			"type": "section",
			"text": {
				"type": "plain_text",
				"text": ":wave: Hey David!\n\nWe'd love to hear from you how we can make this place the best place you’ve ever worked.",
				"emoji": true
			}
		},
		{
			"type": "divider"
		},
		{
			"type": "actions",
			"elements": [
				{
				"type": "button",
				"text": {
					"type": "plain_text",
					"text": "Click Me",
					"emoji": true
				},
				"value": "click_me_123"
			}
			]
		}
	]
}
```

**Expected behavior**
Error is caused:
```
TypeError [ERR_INVALID_ARG_TYPE]: The first argument must be one of type string, Buffer, ArrayBuffer, Array, or Array-like Object. Received type undefined
    at Function.from (buffer.js:200:11)
    at SlackConnector.verifySignature (/MyTinyLittleProject/node_modules/bottender/src/bot/SlackConnector.ts:306:35)
    at SlackConnector.preprocess (/MyTinyLittleProject/node_modules/bottender/src/bot/SlackConnector.ts:336:9)
    at server.use (/MyTinyLittleProject/node_modules/@bottender/express/src/registerRoutes.ts:20:52)
    at Layer.handle [as handle_request] (/MyTinyLittleProject/node_modules/express/lib/router/layer.js:95:5)
    at trim_prefix (/MyTinyLittleProject/node_modules/express/lib/router/index.js:317:13)
    at /MyTinyLittleProject/node_modules/express/lib/router/index.js:284:7
    at Function.process_params (/MyTinyLittleProject/node_modules/express/lib/router/index.js:335:12)
    at next (/MyTinyLittleProject/node_modules/express/lib/router/index.js:275:10)
    at jsonParser (/MyTinyLittleProject/node_modules/@bottender/express/node_modules/body-parser/lib/types/json.js:101:7)
    at Layer.handle [as handle_request] (/MyTinyLittleProject/node_modules/express/lib/router/layer.js:95:5)
    at trim_prefix (/MyTinyLittleProject/node_modules/express/lib/router/index.js:317:13)
    at /MyTinyLittleProject/node_modules/express/lib/router/index.js:284:7
    at Function.process_params (/MyTinyLittleProject/node_modules/express/lib/router/index.js:335:12)
    at next (/MyTinyLittleProject/node_modules/express/lib/router/index.js:275:10)
    at /MyTinyLittleProject/node_modules/@bottender/express/node_modules/body-parser/lib/read.js:130:5
```
