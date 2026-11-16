Burn commmand should always burn one sat
Since the burn command is for burning inscriptions, it should default to burning the minimum amount of BTC possible to burn an inscription, i.e., one sat. (I think OP_RETURN outputs are not required to be above the dust limit.)

Also, I think `--postage` option should be removed, since I can't think of a good reason to specify some other amount of postage, especially because we forbid large values for postage, and the only reason to have customizable postage would be to burn large amounts of BTC along with the inscription.
