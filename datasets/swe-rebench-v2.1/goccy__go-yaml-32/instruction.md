error on parsing block string
environment: go 1.13.4

(日本語でいいでしょうか・・・)

次の様な複数行文字列をパースしている際に文字列中でエラーが発生しました。

``` yaml
foo:
  value: |
     {
      "versions": [
            {
              "status": "CURRENT",
              "updated": "2011-01-21T11:33:21Z",
              "id": "v2.0",
              "links": [
                  {
                      "href": "http://127.0.0.1:8774/v2/",
                      "rel": "self"
                  }
              ]
          },
          {
              "status": "EXPERIMENTAL",
              "updated": "2013-07-23T11:33:21Z",
              "id": "v3.0",
              "links": [
                  {
                      "href": "http://127.0.0.1:8774/v3/",
                      "rel": "self"
                  }
              ]
          }
      ]
     }
```

`.foo.value`以下はすべて文字列となる、という想定で、gopkg.in/yaml.v2では問題なく動作していたものです。
エラーメッセージは次の様なものです。

```
--- FAIL: TestAPIWithExample (0.00s)
    unmarshalyaml_test.go:25: [66:51] failed to parse flow mapping value node
              62 | }
              63 |                             ]
              64 |                         },
              65 |                         {
            > 66 |                             "status": "EXPERIMENTAL",
              67 |                             "updated": "2013-07-23T11:33:21Z",
                                                                    ^
              68 |                             "id": "v3.0",
              69 |                             "links": [
              70 |                                 {
FAIL
```

当該部分は文字列なので、(インデントが足りないとかを除いて)途中でエラーが発生するというのは挙動として正しくないように思えます。

再現用Playground: https://play.golang.org/p/yLh0AZ5lQ62
