Stop interning InterledgerAddress
In runtimes processing lots of STREAM payments, the ILP addresses will look something like `g.{connectorId}.{accountId}.{encryptedStreamInfo}`. For example, `test.jc.money.bob.123xyz`.

In this example, when an ILP address is created, the full address will never be re-used because the  `encryptedStreamInfo` will never be the same from packet to packet. Thus, interning the full address is not a good idea.

That said, it _probably_ is a good idea to keep interning the `InterledgerAddressPrefix` and `AllocationScheme` because these will be duplicated over many packets.
