Is it possible to access original data through preprocesed `BaseRecording` instance
The pipeline
```
Binary File -> Preprocessing -(1)-> Sorting -(2)-> Wave Extractor -(3)-> Neuron feature assessment.
```
The last class gets `BaseRecording` after (1) and uses `get_traces` to compute a spike "fingerprint". Unfortunately, preprocessing removes something we are looking for. Would it be possible to `get_traces` from the original Binary File without reloading it and creating an additional `BaseRecording` object?

In other words, is there something like that
```python
# preproc is BaseRecording (1)
# which is pointing to the filtered and zeroed data
fingerprint = array([
        preproc.original_data.get_traces(
            start_frame   = sp+frmstart,
            end_frame     = sp+frmend).T
        for sp in sp_train
        ])
```

### Additional contract requirements

- `BaseExtractor.get_parent()` returns the parent extractor object when it exists, and `None` otherwise.
- Preprocessing extractors (subclasses of `BasePreprocessor`, such as the recording returned by `spikeinterface.preprocessing.scale`) keep a reference to their source recording, so `preproc.get_parent()` returns the original recording and its data can be read through `preproc.get_parent().get_traces()` without reloading it or creating an additional `BaseRecording`.
