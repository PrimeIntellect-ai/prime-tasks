SchemaFieldNotFoundError When Loading Preprocessed Data
## Current Behavior

When loading preprocessed data using the `Dataset.load()` method with the `preprocessed=True` flag, I encounter a `SchemaFieldNotFoundError` related to the `trialId` column. The preprocessed data already has renamed columns, and the error occurs because the renaming operation is performed again, regardless of whether the data is preprocessed or not.

## Expected Behavior

The preprocessed data should be successfully loaded without any errors.

## Minimum Acceptance Criteria

- [ ] Ensure the `dataset.load(preprocessed=True)` can correctly load preprocessed data without column renaming issues.

## Failure Information (for bugs)

### Steps to Reproduce

1. Load the JuDo1000 public dataset.
2. Perform preprocessing steps like `pix2deg` and `pos2vel`.
3. Save the preprocessed data using `dataset.save()`.
4. Attempt to reload the saved preprocessed data using `dataset.load(preprocessed=True)`.

### Code to Reproduce

```python
dataset = pm.Dataset('JuDo1000', path='/mnt/scratch/chwastek/datasets/Judo1000/')
dataset.download()
dataset.load(subset={'subject_id': 1})

dataset.pix2deg()
dataset.pos2vel(method='savitzky_golay', window_length=7, degree=2)

dataset.save()
dataset.load(preprocessed=True)
```

### Error Log

```python-traceback
---------------------------------------------------------------------------
SchemaFieldNotFoundError                  Traceback (most recent call last)
Cell In[33], line 9
      6 dataset.pos2vel(method='savitzky_golay', window_length=7, degree=2)
      8 dataset.save()
----> 9 dataset.load(preprocessed=True)

File /mnt/scratch/chwastek/anaconda3/lib/python3.11/site-packages/pymovements/dataset/dataset.py:122, in Dataset.load(self, events, preprocessed, subset, events_dirname, preprocessed_dirname, extension)
    119 self.scan()
    120 self.fileinfo = dataset_files.take_subset(fileinfo=self.fileinfo, subset=subset)
--> 122 self.load_gaze_files(
    123     preprocessed=preprocessed, preprocessed_dirname=preprocessed_dirname,
    124     extension=extension,
    125 )
    127 if events:
    128     self.load_event_files(
    129         events_dirname=events_dirname,
    130         extension=extension,
    131     )

File /mnt/scratch/chwastek/anaconda3/lib/python3.11/site-packages/pymovements/dataset/dataset.py:187, in Dataset.load_gaze_files(self, preprocessed, preprocessed_dirname, extension)
    159 """Load all available gaze data files.
    160
    161 Parameters
   (...)
    184     If file type of gaze file is not supported.
    185 """
    186 self._check_fileinfo()
--> 187 self.gaze = dataset_files.load_gaze_files(
    188     definition=self.definition,
    189     fileinfo=self.fileinfo,
    190     paths=self.paths,
    191     preprocessed=preprocessed,
    192     preprocessed_dirname=preprocessed_dirname,
    193     extension=extension,
    194 )
    195 return self

File /mnt/scratch/chwastek/anaconda3/lib/python3.11/site-packages/pymovements/dataset/dataset_files.py:216, in load_gaze_files(definition, fileinfo, paths, preprocessed, preprocessed_dirname, extension)
    205     filepath = paths.get_preprocessed_filepath(
    206         filepath, preprocessed_dirname=preprocessed_dirname,
    207         extension=extension,
    208     )
    210 gaze_data = load_gaze_file(
    211     filepath=filepath,
    212     preprocessed=preprocessed,
    213     custom_read_kwargs=definition.custom_read_kwargs,
    214 )
--> 216 [HIDDEN]
    218 # Add fileinfo columns to dataframe.
    219 gaze_data = add_fileinfo(
    220     definition=definition,
    221     df=gaze_data,
    222     fileinfo=fileinfo_row,
    223 )
    .......
    SchemaFieldNotFoundError: trialId
```

### Relevant Code Snippets

The datasets `DatasetDefinition` describes a `column_map` for renaming columns in the raw input data.

```python
column_map: dict[str, str] = field(
    default_factory=lambda: {
        'trialId': 'trial_id',
        'pointId': 'point_id',
    },
)
```

I tested by running the code with removing the column map, and it worked:

```python
dataset = pm.Dataset('JuDo1000', path='/mnt/scratch/chwastek/datasets/Judo1000/')
dataset.definition.column_map = {}
dataset.load(preprocessed=True)
```

## Context

- Project Version / Commit: 0.17.0
- Operating System: Linux

## Checklist

- [x] I am running the latest version
- [x] I checked the documentation and found no answer
- [x] I checked to make sure that this issue has not already been filed
- [x] I have provided sufficient information for the team
