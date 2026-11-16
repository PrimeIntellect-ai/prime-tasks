Validate rich menu object
NEWS:
https://developers.line.biz/en/news/2022/04/05/release-validate-rich-menu-object/

- [Validate rich menu object](https://developers.line.biz/en/reference/messaging-api/#validate-rich-menu-object)

### Additional contract requirements

Expose rich-menu validation through `Client.ValidateRichMenuObject(RichMenu)`. Its returned call object’s `Do()` method returns `(*BasicResponse, error)`.
