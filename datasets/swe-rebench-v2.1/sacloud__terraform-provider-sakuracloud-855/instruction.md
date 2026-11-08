外部ツール経由でプラン変更された場合のID変更の追跡
### 概要

さくらのクラウドではプラン変更時にリソースのIDが変更される。

対象リソース:
- サーバ
- ルータ
- ELB

Terraformからプラン変更を行なった場合、IDが変更されることへの対応が実装されているが、
外部ツール(AutoScalerなど)からプラン変更が行われた場合にリソースが追跡できなくなる。
これは、各リソースのReadでIDを元にさくらのクラウドAPIを用いてリソースの情報を参照しているため。
(IDで検索し404が返ってきた場合はリソースが削除されたとみなす)

追跡できなくなってもimportすることで復帰させることが出来るが運用的に煩雑。

このため、何らかのルールにしたがって変更前のIDをメタデータとしてリソースに保持しておき、IDでの検索が404になった場合にはメタデータを利用して検索するようにフォールバックする。

### 実装案

`@previous-id=123456789012`のようなタグで変更前のIDを表す。
[HIDDEN]

API呼び出し例: `GET /server?{"Filter":{"Tags.Name":"@previous-id=123456789012"}}`

### Additional contract requirements

- ID-change tracking applies to servers, routers, and enhanced load balancers (ELBs).
- The previous resource ID must be retained as resource metadata using the `@previous-id=<previous ID>` tag convention.
- When lookup by the tracked ID returns 404, the resource must still be found by searching within the same zone for metadata containing the previous tracked ID.
- When that lookup finds the resource, Terraform must track the resource's current ID.
