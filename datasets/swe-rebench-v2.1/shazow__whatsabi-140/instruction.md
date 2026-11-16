Implementation address prefixed with 0s
I was running the proxy detection on the whole Sourcify database and found some anomalies.

One thing is that I saw some FixedProxies for which the implementation address is prefixed with 0s.

See this contract on Sepolia as an example: https://sepolia.etherscan.io/address/0x2f4eeccbe817e2b9f66e8123387aa81bae08dfec

I got this proxy resolver for it:

```
  FixedProxyResolver {
    name: 'FixedProxy',
    resolvedAddress: '0x0000000000000000000000000000000000f7a60f1c88f317f369e3d8679c6689'
  }
```

The actual address should be `0x0000000000f7a60f1c88f317f369e3d8679c6689`.


Might open more issues while I check the data :)
