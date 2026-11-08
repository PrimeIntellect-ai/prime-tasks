Defend against broken cron callback in miner
If the miner code doesn't have any bugs, then the world is a happy place. However, if there are bugs transitively reached by the cron handler such that the handler aborts (and rolls back state), a miner is frozen. This is bad because the miner can't operate, but worse because they also maintain power while being freed from the requirement of submitting PoSts.

This is an area where defensive programming is called for. While we should strive to eliminate abort cases from the miner's cron handler, the power actor should probably remove the miner from the power table if something does go wrong, so at least it fails conservatively.
