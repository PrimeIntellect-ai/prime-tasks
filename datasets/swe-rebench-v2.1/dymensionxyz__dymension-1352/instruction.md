Enforce revision `1` on all rollapps created through the create rollapp tx
Given that a rollapp fork/upgrade is done by the hub, and it's revision is increased, there is no reason to allow for rollapps to register with revision which is not 1. In that case, we can simply let them only choose the name and possibly eip1555.

The advantage of this standartization is that we'll know for sure that rollapps with revision > 1 are forked/upgraded ones.
