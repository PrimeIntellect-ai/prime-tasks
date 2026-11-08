Mock can't override functions that reverts
**Describe the bug**
As spoke over the call with @0xGorilla and your teammates, I believe this is a bug confirmed.

Please take a look at: https://github.com/alxiong/smock/commit/b5774c49a3ab21b06f68cb31866898a3c082b8b6 to reproduce the bug.

for easy reading:
contract function:
```solidity
  function err() external pure returns (bool) {
    revert('Intended throw');
  }
```
testing case:
```typescript
  it('should be able to override throw/revert', async () => {
    mock.err.returns(true);
    // FIXME: somehow, it still passed through
    expect(await mock.err()).to.equal(true);
  })
```
std.err output:
```
  197 passing (9s)
  3 pending
  1 failing

  1) Mock: Call through
       should :
     Error: VM Exception while processing transaction: revert Intended throw
    at Counter.err (test/contracts/mock/Counter.sol:18)
    at HardhatNode._gatherTraces (node_modules/hardhat/src/internal/hardhat-network/provider/node.ts:1077:30)
    at processTicksAndRejections (internal/process/task_queues.js:95:5)
    at runNextTicks (internal/process/task_queues.js:64:3)
    at listOnTimeout (internal/timers.js:526:9)
    at processTimers (internal/timers.js:500:7)
    at HardhatNode.runCall (node_modules/hardhat/src/internal/hardhat-network/provider/node.ts:420:20)
    at EthModule._callAction (node_modules/hardhat/src/internal/hardhat-network/provider/modules/eth.ts:345:9)
    at HardhatNetworkProvider.request (node_modules/hardhat/src/internal/hardhat-network/provider/provider.ts:101:18)
    at EthersProviderWrapper.send (node_modules/@nomiclabs/hardhat-ethers/src/internal/ethers-provider-wrapper.ts:13:20)
```
