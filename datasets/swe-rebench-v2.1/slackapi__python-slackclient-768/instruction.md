Header block support
### Description

Header Block is now available.

https://api.slack.com/reference/block-kit/blocks#header

```js
{
  "type": "header",
  "block_id": "budget-header",
  "text": {
    "type": "plain_text",
    "text": "Budget Performance"
  }
}
```

All we need to do is add `HeaderBlock` class and corresponding tests.

* https://github.com/slackapi/python-slackclient/blob/main/slack/web/classes/blocks.py
* https://github.com/slackapi/python-slackclient/blob/main/tests/web/classes/test_blocks.py

### What type of issue is this? (place an `x` in one of the `[ ]`)
- [ ] bug
- [x] enhancement (feature request)
- [ ] question
- [ ] documentation related
- [ ] testing related
- [ ] discussion

### Requirements (place an `x` in each of the `[ ]`)
* [x] I've read and understood the [Contributing guidelines](https://github.com/slackapi/python-slackclient/blob/master/.github/contributing.md) and have done my best effort to follow them.
* [x] I've read and agree to the [Code of Conduct](https://slackhq.github.io/code-of-conduct).
* [x] I've searched for any related issues and avoided creating a duplicate issue.
