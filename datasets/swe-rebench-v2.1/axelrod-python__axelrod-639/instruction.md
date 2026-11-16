Adding Contrite TfT
This strategy plays like TfT in an environment with no noise. **If there is noise** it has the following added capability:

> If it is defected against because of noise (ie as a mistake) then it responds by cooperating twice.

This requires a bit more information as we don't currently have a way for a player to know if an opponent's play was returned because of noise or not. @marcharper pointed out the [`TrackHistoryTransformer`](http://axelrod.readthedocs.io/en/latest/tutorials/advanced/strategy_transformers.html) which allows a player to track it's own intended play. Perhaps something like that could be used.
