Electron dependencies are now saved twice in the db
As of v0.200.0, each transport graph edge now appears twice in the DB. This occurs because [some logic to check](https://github.com/AgnostiqHQ/covalent/blob/79952e6ea409cb5db359c688c0810bf57742b08b/covalent/_results_manager/result.py#L762) for existing edge entries in the DB was accidentally removed during the recent reorg of DB logic.
