accessing codesize on struct member throws AttributeError: 'Attribute' object has no attribute 'id'
### Version Information

* vyper Version (output of `vyper --version`): 0.3.3
* OS: osx
* Python Version (output of `python --version`): Python 3.8.2

### What's your issue about?

Please include information like:

* full output of the error you received
```AttributeError: 'Attribute' object has no attribute 'id'AttributeError: 'Attribute' object has no attribute 'id'```
* what command you ran ```vyper contract.vy```
* the code that caused the failure:

```# @version 0.3.3

struct ConduitBatch1155Transfer:
    token: address
    _from: address
    to: address
    ids: DynArray[uint256, 10]
    amounts: DynArray[uint256, 10]

SAFEBATCHTRANSFERFROM_MID: constant(Bytes[4]) = method_id("safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)")

@internal
def _performERC1155BatchTransfers(batchTransfers: DynArray[ConduitBatch1155Transfer, 10]):
    for transfer in batchTransfers:
        assert transfer.token.codesize != 0
        _response: Bytes[32] = raw_call(
        transfer.token,
        _abi_encode(
            SAFEBATCHTRANSFERFROM_MID,
            transfer._from,
            transfer.to,
            transfer.ids,
            transfer.amounts
            ),
            max_outsize=32
        )
        if len(_response) > 0:
            assert convert(_response, bool), "SafeBatchTransferFrom failed" ```
