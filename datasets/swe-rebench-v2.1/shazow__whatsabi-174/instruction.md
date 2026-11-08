proxies: contract incorrectly labeled as a proxy tampering the result
Note: I might be completely wrong and maybe it _is_ a proxy, but I'd rather try to explain what's happening naively so someone with better understanding can figure out.

## Overview

When fetching [this contract](https://etherscan.io/address/0xe1164a7a364929c3ba3da9671c8003dd71975d2d#code) (A) with `autoload` and `followProxies: true`, it is labeled as a proxy, and the function ends up following proxies up to [this contract](https://etherscan.io/address/0x03bd8b73d316521c0e65b5672e5be3f174b8a519#code) (B).

### Code

```ts
console.log("Loading contract", contractAddress);
const res = await autoload(contractAddress, {
  provider,
  abiLoader,
  followProxies: true,
  loadContractResult: true,
  onProgress: (p) => {
    console.log(p);
  },
  onError: (e) => {
    console.log(e);
  },
});
console.log("Result", res);
```

### Result

<img width="423" alt="Image" src="https://github.com/user-attachments/assets/c4dd2073-82f7-4de0-8442-9c1f0cc462e3" />

## Details

Setting `followProxies` to `false` produces the expected ABI and source for the provided contract address; which is a factory contract, and is labeled as such.

Contract B is the only proxy listed as proxies of contract A:
<img width="483" alt="Image" src="https://github.com/user-attachments/assets/698d37da-1c4f-458d-b3a4-3b19ee1ce822" />

The contract does not appear to be a proxy according to Etherscan:
<img width="858" alt="Image" src="https://github.com/user-attachments/assets/daf48980-67d6-4c9b-8600-699b768cba5c" />

All of this is ran in the `EtherscanLoader` (as the contract is not verified on Sourcify).

## Links

- [Contract A (fetched) deployment tx](https://etherscan.io/tx/0xaecfdc5c0a46f75ceaca20fc51949993e1f3d5502487a2d43302af6077cf2266)
- [Contract B (resolved) deployment tx](https://etherscan.io/tx/0xd857dcc116905ce491feda2b54f4900f784db61a8a4221be0e39a72b1ee86ce6)

## How to run

```ts
const res = await autoload(contractAddress, {
  provider,
  abiLoader: new loaders.MultiABILoader([
    new loaders.SourcifyABILoader({ chainId: chain.id }),
    new loaders.EtherscanABILoader({
      baseURL: 'https://api.etherscan.io/api',
      apiKey: env.ETHERSCAN_API_KEY,
    }),
  ]),
  followProxies: false, // true will directly follow up to contract B
  loadContractResult: true,
});

console.log('Result', res);

const proxies = await res.followProxies?.();
console.log({ resolvedProxies: proxies }); // will point to contract B
```
