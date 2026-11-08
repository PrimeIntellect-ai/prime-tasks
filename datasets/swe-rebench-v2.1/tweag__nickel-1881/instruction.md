NLS crashes on recursive definitions
**Describe the bug**
`nls` crashes with stack overflow error when parsing nickel source with recursive definition.

**To Reproduce**

Open file with following content in text editor with LSP support and running `nls`.
_I can reproduce it with [lunarvim](https://www.lunarvim.org/), but this should be easily reproduce with vanilla `neovim` or any other text editor._

```nickel
{
  applications = {
    apps | not_exported = applications,
    message = "message",
  }
}
```

**Expected behavior**

Since this is a valid nickel source code, I would expect no `nls` crashes.

```
$ nickel export test.ncl
{
  "applications": {
    "message": "message"
  }
}
```

**Environment**
 - OS name + version:

```
NAME="Fedora Linux"
VERSION="39.20240327.0 (Sericea)"
```

 - Version of the code: From nixpkgs (unstable branch).

```
nickel-lang-cli nickel 1.5.0 (rev cargore)
```

**Additional logs**

```
[START][2024-03-28 10:20:49] LSP logging initiated
[INFO][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:662	"Starting RPC client"	{  args = {},  cmd = "nls",  extra = {    cwd = "/tmp/nickel"  }}
[DEBUG][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:284	"rpc.send"	{  id = 1,  jsonrpc = "2.0",  method = "initialize",  params = {    capabilities = {      textDocument = {        callHierarchy = {          dynamicRegistration = false        },        codeAction = {          codeActionLiteralSupport = {            codeActionKind = {              valueSet = { "", "quickfix", "refactor", "refactor.extract", "refactor.inline", "refactor.rewrite", "source", "source.organizeImports" }            }          },          dataSupport = true,          dynamicRegistration = false,          isPreferredSupport = true,          resolveSupport = {            properties = { "edit" }          }        },        completion = {          completionItem = {            commitCharactersSupport = true,            deprecatedSupport = true,            documentationFormat = { "markdown", "plaintext" },            insertReplaceSupport = true,            insertTextModeSupport = {              valueSet = { 1, 2 }            },            labelDetailsSupport = true,            preselectSupport = true,            resolveSupport = {              properties = { "documentation", "detail", "additionalTextEdits" }            },            snippetSupport = true,            tagSupport = {              valueSet = { 1 }            }          },          completionItemKind = {            valueSet = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25 }          },          completionList = {            itemDefaults = { "commitCharacters", "editRange", "insertTextFormat", "insertTextMode", "data" }          },          contextSupport = true,          dynamicRegistration = false,          insertTextMode = 1        },        declaration = {          linkSupport = true        },        definition = {          linkSupport = true        },        documentHighlight = {          dynamicRegistration = false        },        documentSymbol = {          dynamicRegistration = false,          hierarchicalDocumentSymbolSupport = true,          symbolKind = {            valueSet = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26 }          }        },        hover = {          contentFormat = { "markdown", "plaintext" },          dynamicRegistration = false        },        implementation = {          linkSupport = true        },        publishDiagnostics = {          relatedInformation = true,          tagSupport = {            valueSet = { 1, 2 }          }        },        references = {          dynamicRegistration = false        },        rename = {          dynamicRegistration = false,          prepareSupport = true        },        semanticTokens = {          augmentsSyntaxTokens = true,          dynamicRegistration = false,          formats = { "relative" },          multilineTokenSupport = false,          overlappingTokenSupport = true,          requests = {            full = {              delta = true            },            range = false          },          serverCancelSupport = false,          tokenModifiers = { "declaration", "definition", "readonly", "static", "deprecated", "abstract", "async", "modification", "documentation", "defaultLibrary" },          tokenTypes = { "namespace", "type", "class", "enum", "interface", "struct", "typeParameter", "parameter", "variable", "property", "enumMember", "event", "function", "method", "macro", "keyword", "modifier", "comment", "string", "number", "regexp", "operator", "decorator" }        },        signatureHelp = {          dynamicRegistration = false,          signatureInformation = {            activeParameterSupport = true,            documentationFormat = { "markdown", "plaintext" },            parameterInformation = {              labelOffsetSupport = true            }          }        },        synchronization = {          didSave = true,          dynamicRegistration = false,          willSave = true,          willSaveWaitUntil = true        },        typeDefinition = {          linkSupport = true        }      },      window = {        showDocument = {          support = true        },        showMessage = {          messageActionItem = {            additionalPropertiesSupport = false          }        },        workDoneProgress = true      },      workspace = {        applyEdit = true,        configuration = true,        didChangeWatchedFiles = {          dynamicRegistration = false,          relativePatternSupport = true        },        semanticTokens = {          refreshSupport = true        },        symbol = {          dynamicRegistration = false,          hierarchicalWorkspaceSymbolSupport = true,          symbolKind = {            valueSet = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26 }          }        },        workspaceEdit = {          resourceOperations = { "rename", "create", "delete" }        },        workspaceFolders = true      }    },    clientInfo = {      name = "Neovim",      version = "0.9.5"    },    initializationOptions = vim.empty_dict(),    processId = 2230809,    rootPath = "/tmp/nickel",    rootUri = "file:///tmp/nickel",    trace = "off",    workspaceFolders = { {        name = "/tmp/nickel",        uri = "file:///tmp/nickel"      } }  }}
[DEBUG][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:387	"rpc.receive"	{  id = 1,  jsonrpc = "2.0",  result = {    capabilities = {      codeActionProvider = true,      completionProvider = {        triggerCharacters = { ".", '"', "/" }      },      definitionProvider = true,      documentFormattingProvider = true,      documentSymbolProvider = true,      executeCommandProvider = {        commands = { "eval" }      },      hoverProvider = {        workDoneProgress = false      },      referencesProvider = true,      renameProvider = true,      textDocumentSync = {        change = 1,        openClose = true      }    }  }}
[DEBUG][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:284	"rpc.send"	{  jsonrpc = "2.0",  method = "initialized",  params = vim.empty_dict()}
[INFO][2024-03-28 10:20:49] .../lua/vim/lsp.lua:1344	"LSP[nickel_ls]"	"server_capabilities"	{  server_capabilities = {    codeActionProvider = true,    completionProvider = {      triggerCharacters = { ".", '"', "/" }    },    definitionProvider = true,    documentFormattingProvider = true,    documentSymbolProvider = true,    executeCommandProvider = {      commands = { "eval" }    },    hoverProvider = {      workDoneProgress = false    },    referencesProvider = true,    renameProvider = true,    textDocumentSync = {      change = 1,      openClose = true    }  }}
[DEBUG][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:284	"rpc.send"	{  jsonrpc = "2.0",  method = "textDocument/didOpen",  params = {    textDocument = {      languageId = "nickel",      text = '{\n  applications = {\n    apps | not_exported = applications,\n    message = "message",\n  }\n} \n',      uri = "file:///tmp/nickel/test.ncl",      version = 0    }  }}
[DEBUG][2024-03-28 10:20:49] .../lua/vim/lsp.lua:1391	"LSP[nickel_ls]"	"client.request"	1	"textDocument/documentSymbol"	{  textDocument = {    uri = "file:///tmp/nickel/test.ncl"  }}	<function 1>	1
[DEBUG][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:284	"rpc.send"	{  id = 2,  jsonrpc = "2.0",  method = "textDocument/documentSymbol",  params = {    textDocument = {      uri = "file:///tmp/nickel/test.ncl"    }  }}
[DEBUG][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:387	"rpc.receive"	{  jsonrpc = "2.0",  method = "textDocument/publishDiagnostics",  params = {    diagnostics = {},    uri = "file:///tmp/nickel/test.ncl"  }}
[ERROR][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:734	"rpc"	"nls"	"stderr"	"\nthread 'main' has overflowed its stack\nfatal runtime error: stack overflow\n"
[ERROR][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:734	"rpc"	"nls"	"stderr"	"\nthread 'main' has overflowed its stack\nfatal runtime error: stack overflow\n"
[DEBUG][2024-03-28 10:20:49] .../lua/vim/lsp.lua:1391	"LSP[nickel_ls]"	"client.request"	1	"textDocument/documentSymbol"	{  textDocument = {    uri = "file:///tmp/nickel/test.ncl"  }}	<function 1>	1
[DEBUG][2024-03-28 10:20:49] .../vim/lsp/rpc.lua:284	"rpc.send"	{  id = 3,  jsonrpc = "2.0",  method = "textDocument/documentSymbol",  params = {    textDocument = {      uri = "file:///tmp/nickel/test.ncl"    }  }}
```

### Additional contract requirements

- A `textDocument/documentSymbol` request for a document containing a recursive record definition must complete without crashing and return a finite symbol hierarchy.
