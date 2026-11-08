Language server crash on `"initializationOptions": null`
When using the language server via other editors than VSCode (Emacs, neovim, ...), if one has `initializationOptions` set to `null` (which the LSP spec allows, I think), the server crashes in LSP4J.

```
~>
java.lang.IllegalStateException: Not a JSON Object: null
    at com.google.gson.JsonElement.getAsJsonObject(JsonElement.java:165)
```

<details>
  <summary>Trace</summary>

```

[Trace - 09:38:33 AM] Sending request 'initialize - (3)'.
Params: {
  "processId": 2070,
  "rootPath": "/$USER/prague-tutorial",
  "clientInfo": {
    "name": "emacs",
    "version": "GNU Emacs 30.1 (build 1, x86_64-pc-linux-gnu, GTK+ Version 3.24.49, cairo version 1.18.2)"
  },
  "rootUri": "file:///$USER/prague-tutorial",
  "capabilities": {
    "general": {
      "positionEncodings": [
        "utf-32",
        "utf-16"
      ]
    },
    "workspace": {
      "workspaceEdit": {
        "documentChanges": true,
        "resourceOperations": [
          "create",
          "rename",
          "delete"
        ]
      },
      "applyEdit": true,
      "symbol": {
        "symbolKind": {
          "valueSet": [
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
            19,
            20,
            21,
            22,
            23,
            24,
            25,
            26
          ]
        }
      },
      "executeCommand": {
        "dynamicRegistration": false
      },
      "didChangeWatchedFiles": {
        "dynamicRegistration": true
      },
      "workspaceFolders": true,
      "configuration": true,
      "codeLens": {
        "refreshSupport": true
      },
      "diagnostics": {
        "refreshSupport": false
      },
      "fileOperations": {
        "didCreate": false,
        "willCreate": false,
        "didRename": true,
        "willRename": true,
        "didDelete": false,
        "willDelete": false
      }
    },
    "textDocument": {
      "declaration": {
        "dynamicRegistration": true,
        "linkSupport": true
      },
      "definition": {
        "dynamicRegistration": true,
        "linkSupport": true
      },
      "references": {
        "dynamicRegistration": true
      },
      "implementation": {
        "dynamicRegistration": true,
        "linkSupport": true
      },
      "typeDefinition": {
        "dynamicRegistration": true,
        "linkSupport": true
      },
      "synchronization": {
        "willSave": true,
        "didSave": true,
        "willSaveWaitUntil": true
      },
      "documentSymbol": {
        "symbolKind": {
          "valueSet": [
            1,
            2,
            3,
            4,
            5,
            6,
            7,
            8,
            9,
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
            19,
            20,
            21,
            22,
            23,
            24,
            25,
            26
          ]
        },
        "hierarchicalDocumentSymbolSupport": true
      },
      "formatting": {
        "dynamicRegistration": true
      },
      "rangeFormatting": {
        "dynamicRegistration": true
      },
      "onTypeFormatting": {
        "dynamicRegistration": true
      },
      "rename": {
        "dynamicRegistration": true,
        "prepareSupport": true
      },
      "codeAction": {
        "dynamicRegistration": true,
        "isPreferredSupport": true,
        "codeActionLiteralSupport": {
          "codeActionKind": {
            "valueSet": [
              "",
              "quickfix",
              "refactor",
              "refactor.extract",
              "refactor.inline",
              "refactor.rewrite",
              "source",
              "source.organizeImports"
            ]
          }
        },
        "resolveSupport": {
          "properties": [
            "edit",
            "command"
          ]
        },
        "dataSupport": true
      },
      "completion": {
        "completionItem": {
          "snippetSupport": false,
          "documentationFormat": [
            "markdown",
            "plaintext"
          ],
          "resolveAdditionalTextEditsSupport": true,
          "insertReplaceSupport": true,
          "deprecatedSupport": true,
          "resolveSupport": {
            "properties": [
              "documentation",
              "detail",
              "additionalTextEdits",
              "command",
              "insertTextFormat",
              "insertTextMode"
            ]
          },
          "insertTextModeSupport": {
            "valueSet": [
              1,
              2
            ]
          }
        },
        "contextSupport": true,
        "dynamicRegistration": true
      },
      "signatureHelp": {
        "signatureInformation": {
          "parameterInformation": {
            "labelOffsetSupport": true
          }
        },
        "dynamicRegistration": true
      },
      "documentLink": {
        "dynamicRegistration": true,
        "tooltipSupport": true
      },
      "hover": {
        "contentFormat": [
          "markdown",
          "plaintext"
        ],
        "dynamicRegistration": true
      },
      "foldingRange": {
        "dynamicRegistration": true
      },
      "selectionRange": {
        "dynamicRegistration": true
      },
      "callHierarchy": {
        "dynamicRegistration": false
      },
      "typeHierarchy": {
        "dynamicRegistration": true
      },
      "publishDiagnostics": {
        "relatedInformation": true,
        "tagSupport": {
          "valueSet": [
            1,
            2
          ]
        },
        "versionSupport": true
      },
      "diagnostic": {
        "dynamicRegistration": false,
        "relatedDocumentSupport": false
      },
      "linkedEditingRange": {
        "dynamicRegistration": true
      }
    },
    "window": {
      "workDoneProgress": true,
      "showDocument": {
        "support": true
      }
    }
  },
  "initializationOptions": null,
  "workDoneToken": "1"
}


[Trace - 09:38:34 AM] Received response 'initialize - (3)' in 371ms.
Result: {
  "code": -32603,
  "message": "Internal error.",
  "data": "java.lang.IllegalStateException: Not a JSON Object: null\n\tat com.google.gson.JsonElement.getAsJsonObject(JsonElement.java:165)\n\t[HIDDEN]\n\tat java.base/jdk.internal.reflect.DirectMethodHandleAccessor.invoke(DirectMethodHandleAccessor.java:103)\n\tat java.base/java.lang.reflect.Method.invoke(Method.java:580)\n\tat org.eclipse.lsp4j.jsonrpc.services.GenericEndpoint.lambda$recursiveFindRpcMethods$0(GenericEndpoint.java:65)\n\tat org.eclipse.lsp4j.jsonrpc.services.GenericEndpoint.request(GenericEndpoint.java:128)\n\tat org.eclipse.lsp4j.jsonrpc.RemoteEndpoint.handleRequest(RemoteEndpoint.java:271)\n\tat org.eclipse.lsp4j.jsonrpc.RemoteEndpoint.consume(RemoteEndpoint.java:201)\n\tat org.eclipse.lsp4j.jsonrpc.json.StreamMessageProducer.handleMessage(StreamMessageProducer.java:185)\n\tat org.eclipse.lsp4j.jsonrpc.json.StreamMessageProducer.listen(StreamMessageProducer.java:97)\n\tat org.eclipse.lsp4j.jsonrpc.json.ConcurrentMessageProcessor.run(ConcurrentMessageProcessor.java:114)\n\tat java.base/java.util.concurrent.Executors$RunnableAdapter.call(Executors.java:572)\n\tat java.base/java.util.concurrent.FutureTask.run(FutureTask.java:317)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor.runWorker(ThreadPoolExecutor.java:1144)\n\tat java.base/java.util.concurrent.ThreadPoolExecutor$Worker.run(ThreadPoolExecutor.java:642)\n\tat java.base/java.lang.Thread.run(Thread.java:1583)\n"
}
```

</details>

### Additional contract requirements

- The language server must successfully complete the LSP `initialize` request when `initializationOptions` is JSON `null`, without crashing.
