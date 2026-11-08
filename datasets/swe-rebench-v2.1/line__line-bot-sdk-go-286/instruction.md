Support rich menu switch action
- Rich menu switch action has been added to action object
- postback.params object for rich menu switch action has been added to Postback event

https://developers.line.biz/en/news/2021/06/21/switch-between-multiple-rich-menus/

this is related to #284 .

### Additional contract requirements

- The postback parameters object must carry the rich-menu switch fields: the target rich menu alias id (JSON `newRichMenuAliasId`, exposed as `NewRichMenuAliasID`) and the switch result status (JSON `status`, exposed as `Status`). A postback event whose `params` contains these values must parse them and re-serialize them under the same JSON names.
- A rich menu switch action in the rich menu action object must use the type value `richmenuswitch` and carry the target rich menu alias id in a `richMenuAliasId` property.
