TypeError: 'NoneType' object is not iterable
OpenNMT-tf v2.1.0
Python v3.5.2
tensorflow-gpu v2.0.0

```
model_dir: toy_enru_transformer_withalign

data:
  train_features_file: data/train.en
  train_labels_file: data/train.ru
  train_alignments: data/train.align
  eval_features_file: data/valid.en
  eval_labels_file: data/valid.ru
  source_vocabulary: data/mdl-en.vocab
  target_vocabulary: data/mdl-ru.vocab

params:
  guided_alignment_type: "ce"
  guided_alignment_weight: 1.0

train:
  save_checkpoints_steps: 1000

eval:
  external_evaluators: BLEU
  export_on_best: bleu
  early_stopping:
    metric: bleu
    min_improvement: 0.01
    steps: 4

infer:
  batch_size: 32
```

```
Traceback (most recent call last):
  File "/usr/local/bin/onmt-main", line 8, in <module>
    sys.exit(main())
  File "/usr/local/lib/python3.5/dist-packages/opennmt/bin/main.py", line 189, in main
    checkpoint_path=args.checkpoint_path)
  File "/usr/local/lib/python3.5/dist-packages/opennmt/runner.py", line 205, in train
    export_on_best=eval_config.get("export_on_best"))
  File "/usr/local/lib/python3.5/dist-packages/opennmt/training.py", line 70, in __call__
    self._model.create_variables(optimizer=self._optimizer)
  File "/usr/local/lib/python3.5/dist-packages/opennmt/models/model.py", line 271, in create_variables
    features = self.examples_inputter.make_features(features=features, training=True)
  File "/usr/local/lib/python3.5/dist-packages/opennmt/models/sequence_to_sequence.py", line 426, in make_features
    element, alignment = element
TypeError: 'NoneType' object is not iterable
```

https://github.com/OpenNMT/OpenNMT-tf/blob/bec38f98de000361b0ce017cc86b9f8d0d2815c9/opennmt/models/model.py#L271

https://github.com/OpenNMT/OpenNMT-tf/blob/bec38f98de000361b0ce017cc86b9f8d0d2815c9/opennmt/models/sequence_to_sequence.py#L433-L435

Trying to unpack a `NoneType` tuple. [HIDDEN]
This looks like a bug. Can you actually train a model on v2.1.0?

### Additional contract requirements

- For the configuration shown, creating model variables during training setup must not raise the reported `TypeError: 'NoneType' object is not iterable`.
