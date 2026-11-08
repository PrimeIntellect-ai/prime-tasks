_read_events errors on BAD_ACQ_SKIP
### Description of the problem

I have a MEG FIF dataset that mostly doesn't have annotations (only the occasional `BAD_ACQ_SKIP`), and does have stim-channel events (which I parse beforehand and pass in as an events array). I would expect the `BAD_ACQ_SKIP` annotation to be silently preserved in the Raw file, but in fact `write_raw_bids` fails because there is no entry for `BAD_ACQ_SKIP` in the event ID dictionary.

Am I just missing something obvious here?  I've not actually used mne-bids very much so it's quite possible I'm just doing it wrong.

### Steps to reproduce

```Python
import mne
from mne_bids import BIDSPath, write_raw_bids


raw_path = mne.datasets.sample.data_path() / "MEG" / "sample" / "sample_audvis_raw.fif"

raw = mne.io.read_raw_fif(raw_path).crop(tmax=5).load_data()
raw.set_annotations(mne.Annotations([2], [0.2], ["BAD_ACQ_SKIP"]))

events = mne.find_events(raw)
event_id = dict(foo=1, bar=2, baz=3)

bp = BIDSPath(root="/home/drmccloy/Desktop/tmp-mwe", subject="sample", task="audvis")
write_raw_bids(
    raw,
    bids_path=bp,
    events=events,
    event_id=event_id,
    allow_preload=True,
    format="FIF",
)
```


### Expected results

file is written

### Actual results

```

------------------------------------------------------------------
ValueError                       Traceback (most recent call last)
Cell In[1], line 14
     11 event_id = dict(foo=1, bar=2, baz=3)
     13 bp = BIDSPath(root="/home/drmccloy/Desktop/tmp-mwe", subject="sample", task="audvis")
---> 14 write_raw_bids(
     15     raw,
     16     bids_path=bp,
     17     events=events,
     18     event_id=event_id,
     19     allow_preload=True,
     20     format="FIF",
     21 )

File <decorator-gen-445>:12, in write_raw_bids(raw, bids_path, events, event_id, anonymize, format, symlink, empty_room, allow_preload, montage, acpc_aligned, overwrite, verbose)

File /opt/mne/bids/mne_bids/write.py:1979, in write_raw_bids(raw, bids_path, events, event_id, anonymize, format, symlink, empty_room, allow_preload, montage, acpc_aligned, overwrite, verbose)
   1977 # Write events.
   1978 if not data_is_emptyroom:
-> 1979     events_array, event_dur, event_desc_id_map = _read_events(
   1980         events, event_id, raw, bids_path=bids_path
   1981     )
   1982     if events_array.size != 0:
   1983         _events_tsv(
   1984             events=events_array,
   1985             durations=event_dur,
   (...)
   1989             overwrite=overwrite,
   1990         )

File /opt/mne/bids/mne_bids/read.py:158, in _read_events(events, event_id, raw, bids_path)
    154         desc_without_id = sorted(
    155             set(raw.annotations.description) - set(event_id.keys())
    156         )
    157         if desc_without_id:
--> 158             raise ValueError(
    159                 f"The provided raw data contains annotations, but "
    160                 f'"event_id" does not contain entries for all annotation '
    161                 f"descriptions. The following entries are missing: "
    162                 f'{", ".join(desc_without_id)}'
    163             )
    165 # If we have events, convert them to Annotations so they can be easily
    166 # merged with existing Annotations.
    167 if events.size > 0:

ValueError: The provided raw data contains annotations, but "event_id" does not contain entries for all annotation descriptions. The following entries are missing: BAD_ACQ_SKIP

```

### Additional information

```

Platform             Linux-5.10.0-29-amd64-x86_64-with-glibc2.31
Python               3.12.3 | packaged by conda-forge | (main, Apr 15 2024, 18:38:13) [GCC 12.3.0]
Executable           /opt/mambaforge/envs/mnedev/bin/python3.12
CPU                   (12 cores)
Memory               62.7 GB

Core
├☑ mne               1.8.0.dev16+g768e5b322 (devel, latest release is 1.7.0)
├☑ numpy             1.26.4 (OpenBLAS 0.3.23.dev with 12 threads)
├☑ scipy             1.13.1
└☑ matplotlib        3.9.0 (backend=qtagg)

Numerical (optional)
├☑ sklearn           1.5.0
├☑ numba             0.59.1
├☑ nibabel           5.2.1
├☑ nilearn           0.10.4
├☑ dipy              1.9.0
├☑ openmeeg          2.5.10
├☑ pandas            2.2.2
├☑ h5io              0.2.2
├☑ h5py              3.11.0
└☐ unavailable       cupy

Visualization (optional)
├☑ pyvista           0.43.8 (OpenGL 4.6 (Core Profile) Mesa 21.2.6 via Mesa Intel(R) UHD Graphics (CML GT2))
├☑ pyvistaqt         0.11.0
├☑ vtk               9.3.0
├☑ qtpy              2.4.1 (PyQt6=6.7.0)
├☑ ipympl            0.9.4
├☑ pyqtgraph         0.13.7
├☑ mne-qt-browser    0.7.0.dev12+g1c9819a
├☑ ipywidgets        8.1.3
├☑ trame_client      3.0.3
├☑ trame_server      3.0.0
├☑ trame_vtk         2.8.8
└☑ trame_vuetify     2.5.0

Ecosystem (optional)
├☑ mne-bids          0.15.0.dev54+gc87a8233
├☑ mne-nirs          0.7.0.dev0
├☑ mne-connectivity  0.7.0.dev0
├☑ neo               0.13.1
├☑ eeglabio          0.0.2-4
├☑ edfio             0.4.2
├☑ mffpy             0.9.0
├☑ pybv              0.7.5
└☐ unavailable       mne-features, mne-icalabel, mne-bids-pipeline

```
