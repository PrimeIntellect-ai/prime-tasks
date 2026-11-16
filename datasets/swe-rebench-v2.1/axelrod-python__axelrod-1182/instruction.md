function 'compute_features' in ANN.py
Thanks for your work. line 72 in ANN.py, 'my_previous_d = 0 if player.history[-1] == D else 0', i think it should be '[HIDDEN]'.
Is it a typo or you did that on purpose?  And is the weights trained under this code?
Looking forward for ur reply, thanks.

### Additional contract requirements

The shipped pretrained ANN variants must remain usable with the corrected 17-feature history representation. They must be able to choose actions during ordinary play without errors; no particular action trace against a particular opponent is required. In that representation, the feature for the player’s previous action must be 1 when that action was D and 0 when it was C.
