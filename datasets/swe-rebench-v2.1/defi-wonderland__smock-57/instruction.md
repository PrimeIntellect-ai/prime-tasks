EVM Reset bug
**Describe the bug**
Calling `evm.reset()` blocks the creation of a new fake.

**Reproduction steps**

```typescript
const fake1 = await smock.fake('MyContract');
await fake1.callStatic.something(); // will be fine

await network.provider.request({
    method: 'hardhat_reset',
    params: [],
});

const fake2 = await smock.fake('MyOtherContract');
await fake2.callStatic.somethingElse(); // will revert
```

**Expected behavior**
`fake2` should be mocked, and behave as such. N items should be able to be mocked.

**System Specs:**

- OS: Ubuntu 20.04
- Package Version (or commit hash): This happend with hardhat 2.5.0, and also with 2.6.1. Also ethers 5.4.1 and 5.4.3

**Additional context**
Showed with @0xGorilla how to reproduce.
