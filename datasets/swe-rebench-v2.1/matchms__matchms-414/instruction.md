Fix use of FingerprintSimilarity in Pipelines
**Describe the bug**
Computation using Pipelines fails with a quite elusive bug.

**To Reproduce**
```python
from matchms.similarity import MetadataMatch, FingerprintSimilarity
from matchms.importing import load_from_msp, scores_from_json
from matchms import Scores, set_matchms_logger_level
from matchms.filtering import add_fingerprint
from matchms import Pipeline
set_matchms_logger_level("WARNING")

pipeline = Pipeline()
pipeline.query_files = filename
pipeline.reference_files = filename

filter_steps = [
    ["default_filters"],
    ["add_fingerprint"],
    ["require_minimum_number_of_peaks", {"n_required": 5}]
]
pipeline.filter_steps_queries = filter_steps
pipeline.filter_steps_refs = filter_steps

pipeline.score_computations = [
    ["metadatamatch", {"field": "precursor_mz", "matching_type": "difference", "tolerance": 50}],
    ["fingerprintsimilarity", {"similarity_measure": "jaccard"}],
    ["metadatamatch", {"field": "retention_index", "matching_type": "difference", "tolerance": 20}],
    #["cosinegreedy",  {"tolerance": 0.5}]
]

pipeline.run()

scores = pipeline.scores
```

**Screenshots**
```
Output exceeds the [size limit](command:workbench.action.openSettings?%5B%22notebook.output.textLineLimit%22%5D). Open the full output data [in a text editor](command:workbench.action.openLargeOutput?94bd4245-8db1-4ee8-9171-cb7272009071)
---------------------------------------------------------------------------
TypingError                               Traceback (most recent call last)
Cell In[3], line 20
     11 pipeline.filter_steps_refs = filter_steps
     13 pipeline.score_computations = [
     14     ["metadatamatch", {"field": "precursor_mz", "matching_type": "difference", "tolerance": 50}],
     15     ["fingerprintsimilarity", {"similarity_measure": "jaccard"}],
     16     ["metadatamatch", {"field": "retention_index", "matching_type": "difference", "tolerance": 20}],
     17     #["cosinegreedy",  {"tolerance": 0.5}]
     18 ]
---> 20 pipeline.run()
     22 scores = pipeline.scores

File [c:\Users\473355\Miniconda3\envs\matchms-pipeline\lib\site-packages\matchms\Pipeline.py:167](file:///C:/Users/473355/Miniconda3/envs/matchms-pipeline/lib/site-packages/matchms/Pipeline.py:167), in Pipeline.run(self)
    165     else:
    166         self.write_to_logfile(f"-- Score computation: {computation} --")
--> 167         self._apply_similarity_measure(computation, i)
    168 self.write_to_logfile(f"--- Pipeline run finised ({str(datetime.now())}) ---")

File [c:\Users\473355\Miniconda3\envs\matchms-pipeline\lib\site-packages\matchms\Pipeline.py:204](file:///C:/Users/473355/Miniconda3/envs/matchms-pipeline/lib/site-packages/matchms/Pipeline.py:204), in Pipeline._apply_similarity_measure(self, computation, i)
    198     self.scores = calculate_scores(self.spectrums_references,
    199                                    self.spectrums_queries,
    200                                    similarity_measure,
    201                                    array_type="sparse",
    202                                    is_symmetric=self.is_symmetric)
...

    jaccard_score = 0
    if u_or_v.sum() != 0:
```

### Additional contract requirements

When minimum-peak filtering is configured for query and reference spectra, the pipeline must complete score computation using the spectra that survive filtering; rejected spectra must not cause survivors to be skipped or corrupt the scoring results.
