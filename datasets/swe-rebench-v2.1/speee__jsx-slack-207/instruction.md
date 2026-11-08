<Mrkdwn raw>
`<Mrkdwn raw>` is an idea to provide the solution for #160 right out of the box.

If enabled `raw` attribute, `<Mrkdwn>` won't parse the children as HTML that requires escaping some characters, and set the text to the content of `text` JSON field as is.

```jsx
console.log(
  <Mrkdwn>
    {'Hey <@U024BE7LH>, thanks for submitting your report.'}
  </Mrkdwn>
)
// {
//   "type": "mrkdwn",
//   "text": "Hey &lt;@U024BE7LH&gt;, thanks for submitting your report."
// }

console.log(
  <Mrkdwn raw>
    {'Hey <@U024BE7LH>, thanks for submitting your report.'}
  </Mrkdwn>
)
// {
//   "type": "mrkdwn",
//   "text": "Hey <@U024BE7LH>, thanks for submitting your report."
// }
```

It can avoid escaping `<` and `>` by jsx-slack so would be useful for using the raw mrkdwn text, that is included [advanced formatting with special parsing](https://api.slack.com/reference/surfaces/formatting#advanced).
