buildIncomplete fails for unsigned P2SH inputs
I am trying to write test cases for sending an unsigned transaction P2SH transaction to my service, but I'm unable to get the hex because the `buildIncomplete` function fails with a strange error. See below for bug repro:

```
var b = require('bitcoinjs-lib');
var inp = Buffer.from('010000000173120703f67318aef51f7251272a6816d3f7523bb25e34b136d80be959391c100000000000ffffffff0100c817a80400000017a91471a8ec07ff69c6c4fee489184c462a9b1b9237488700000000', 'hex') // arbitrary P2SH input
var inpTx = b.Transaction.fromBuffer(inp)

var txb = new b.TransactionBuilder(b.networks.testnet)
txb.addInput(inpTx, 0)
txb.addOutput(b.address.toOutputScript('2NAkqp5xffoomp5RLBcakuGpZ12GU4twdz4', b.networks.testnet), 1e8) // arbitrary output

txb.buildIncomplete()
```

produces the error

```
Error: Impossible to sign this type
    at buildInput (/Users/alex/dev/bitcoinjs-lib/src/transaction_builder.js:408:13)
    at /Users/alex/dev/bitcoinjs-lib/src/transaction_builder.js:614:18
    at Array.forEach (native)
    at TransactionBuilder.__build (/Users/alex/dev/bitcoinjs-lib/src/transaction_builder.js:611:15)
    at TransactionBuilder.buildIncomplete (/Users/alex/dev/bitcoinjs-lib/src/transaction_builder.js:600:15)
    at repl:1:5
    at sigintHandlersWrap (vm.js:22:35)
    at sigintHandlersWrap (vm.js:96:12)
    at ContextifyScript.Script.runInThisContext (vm.js:21:12)
    at REPLServer.defaultEval (repl.js:346:29)

```

[HIDDEN] I would write up a PR but don't know enough about bitcoinjs-lib to know if this is a simple fix or requires a deeper reworking of the txn build/sign flow. Suggestions appreciated!

### Additional contract requirements

- For the demonstrated unsigned P2SH input, `buildIncomplete()` must return a transaction that can be serialized to hex instead of throwing `Impossible to sign this type`.
