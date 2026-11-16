Reuse up to `max_examples` examples when generation is disabled
https://github.com/HypothesisWorks/hypothesis/blob/caccabbd107757ee6e9de1de7e3cff5474d9ccc5/hypothesis-python/src/hypothesis/internal/conjecture/engine.py#L544

No matter how many examples are in the database, we'll use at most 10% of our example budget replaying them - even if the generation phase is disabled.  It would be nice if we could replay up to `max_examples` when `Phase.generate not in self.settings.phases`.
