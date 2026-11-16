mark-callable-contracts rule is firing a false positive on emitting events
The `mark-callable-contracts` rule is being triggered against emitting events, as events are camel-cased very similarly to contracts. We should update this rule so that it does not get triggered by emitting an event. Take for instance this example:
```sol
contract A {
  event UpdatedToken();

  function b() public {
    emit UpdatedToken(); // This line triggers mark-callable-contracts
  }

}
```
