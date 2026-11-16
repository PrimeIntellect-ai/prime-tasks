Single line doc blocks not supported?
## Summary
Phpactor seems to not support single line comments that are supported by Phpdoc
[Tests are all targeted at multi line](https://github.com/phpactor/phpactor/tree/master/lib/DocblockParser/Tests/Unit/Printer/examples). Any plans to support this?

I would love to give it a go, if I can manage to get a development environment up and running for Phpactor


## Single line comment
Single line comment (no comment shown)
![image](https://github.com/phpactor/phpactor/assets/1260209/8969a5d7-f2b0-4cd5-8036-2d82398eec77)

Server log:
```
[DEBUG][2023-08-21 09:42:23] .../lua/vim/lsp.lua:1392	"LSP[phpactor]"	"client.request"	1	"textDocument/hover"	{  position = {    character = 20,    line = 11  },  textDocument = {    uri = "file:///home/dmitri/sites/meg-worktree/feature/tests/Unit/ATest.php"  }}	<function 1>	1
[DEBUG][2023-08-21 09:42:23] .../vim/lsp/rpc.lua:284	"rpc.send"	{  id = 2,  jsonrpc = "2.0",  method = "textDocument/hover",  params = {    position = {      character = 20,      line = 11    },    textDocument = {      uri = "file:///home/dmitri/sites/meg-worktree/feature/tests/Unit/ATest.php"    }  }}
[DEBUG][2023-08-21 09:42:24] .../vim/lsp/rpc.lua:387	"rpc.receive"	{  id = 2,  jsonrpc = "2.0",  result = {    contents = {      kind = "markdown",      value = "### ATest # singleLineComment\n\n```php\n<?php public function singleLineComment(): void\n```"    },    range = {      ["end"] = {        character = 37,        line = 11      },      start = {        character = 20,        line = 11      }    }  }}
```


## Multi line comment

Multi line comment (comment is shown)
![image](https://github.com/phpactor/phpactor/assets/1260209/76eaf622-05da-41d0-9558-fb25391a5739)


Server log:

```
[DEBUG][2023-08-21 09:43:59] .../lua/vim/lsp.lua:1392	"LSP[phpactor]"	"client.request"	1	"textDocument/hover"	{  position = {    character = 20,    line = 19  },  textDocument = {    uri = "file:///home/dmitri/sites/meg-worktree/feature/tests/Unit/ATest.php"  }}	<function 1>	1
[DEBUG][2023-08-21 09:43:59] .../vim/lsp/rpc.lua:284	"rpc.send"	{  id = 3,  jsonrpc = "2.0",  method = "textDocument/hover",  params = {    position = {      character = 20,      line = 19    },    textDocument = {      uri = "file:///home/dmitri/sites/meg-worktree/feature/tests/Unit/ATest.php"    }  }}
[DEBUG][2023-08-21 09:43:59] .../vim/lsp/rpc.lua:387	"rpc.receive"	{  id = 3,  jsonrpc = "2.0",  result = {    contents = {      kind = "markdown",      value = "### ATest # multipleLineComment\n\nThis is a\nmulti-line comment\n\n```php\n<?php public function multipleLineComment(): void\n```"    },    range = {      ["end"] = {        character = 39,        line = 19      },      start = {        character = 20,        line = 19      }    }  }}
```


## PHPDoc support

I double checked if this feature is supported by phpdoc

From [PhpDocumentor](https://docs.phpdoc.org/3.0/guide/guides/docblocks.html)

> A DocComment starts with a forward slash and two asterisks (/**), which is similar to how you start a multiline comment but with an additional asterisk, and ends with an asterisk and forward slash (*/). DocComments may be a single line in size but may also span multiple lines, in which case each line must start with an asterisk. It is customary, and recommended, to align the asterisks vertically when spanning multiple lines.
>
> So, a single line DocComment looks like this:
>
> ```php
> /** This is a single line DocComment. */
> ```
>
> And a multiline DocComment looks like this:
>
> ```php
> /**
>  * This is a multi-line DocComment.
>  */
> ```
