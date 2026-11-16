Duplicate event entries with identical hashes for unverified contracts
WhatsABI is generating duplicate event ABI entries with the same hashes when attempting to `autoload` the ABI for some contracts.

## Steps to reproduce
Run `autoload` on the address with no ABIoader and let WhatsABI guess the ABI.

**Example contract**
https://etherscan.io/address/0xd9db270c1b5e3bd161e8c8503c55ceabee709552#code

**Sample ABI (irrelevant entries omitted)**
```json
{
  "address": "0xd9db270c1b5e3bd161e8c8503c55ceabee709552",
  "abi": [
    {
      "type": "event",
      "hash": "0x9465fa0c962cc76958e6373a993326400c1c94f8be2fe3a952adfa7f60b2ea26",
      "sig": "AddedOwner(address)",
      "anonymous": false,
      "name": "AddedOwner",
      "inputs": [
        {
          "type": "address",
          "name": ""
        }
      ]
    },
    {
      "type": "event",
      "hash": "0x9465fa0c962cc76958e6373a993326400c1c94f8be2fe3a952adfa7f60b2ea26",
      "sig": "AddedOwner(address)",
      "anonymous": false,
      "name": "AddedOwner",
      "inputs": [
        {
          "type": "address",
          "name": ""
        }
      ]
    }
  ],
  "proxies": []
}
```

## Expected behavior
Each event should be unique within the ABI with no duplicate entries for the same event hash.

### Additional contract requirements

- When `disasm` is run on the bytecode of `0xd9db270c1b5e3bd161e8c8503c55ceabee709552`, `Array.from(result.eventCandidates).length` must be `14`.
