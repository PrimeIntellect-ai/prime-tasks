Remove v4 network upgrades from v5 code
With new major version 5 we should drop any in-code switches on network version that applied in earlier versions.
- miner.CanCommitSealProof
- miner.CanExtendSealProofType
- builtin.SealProofSectorMaximumLifetime
