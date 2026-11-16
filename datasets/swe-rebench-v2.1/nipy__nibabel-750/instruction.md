Cannot set values in GIFTI data array loaded from file
Dear numpy experts,

I am running fmriprep on singularity with a version 3.01 image

and my whole 76 subjects dataset run in parallel are crashing on our HPC and give this error message:

"
Node:
fmriprep_wf.single_subject_109_wf.func_preproc_ses_1_task_restingstate_wf.bold_surf_wf.medial_nans
Working directory: /mnt/data/loic2/work/fmriprep_wf/single_subject_109_wf/func_preproc_ses_1_task_restingstate_wf/bold_surf_wf/_hemi_rh/medial_nans

Node inputs:

in_file = ['/mnt/data/loic2/work/fmriprep_wf/single_subject_109_wf/func_preproc_ses_1_task_restingstate_wf/bold_surf_wf/_hemi_rh/sampler/mapflow/_sampler0/rh.fsaverage5.gii']
subjects_dir = <undefined>
target_subject = ['fsaverage5']

Traceback (most recent call last):
  File "/usr/local/miniconda/lib/python3.7/site-packages/nipype/pipeline/plugins/multiproc.py", line 69, in run_node
    result['result'] = node.run(updatehash=updatehash)
  File "/usr/local/miniconda/lib/python3.7/site-packages/nipype/pipeline/engine/nodes.py", line 473, in run
    result = self._run_interface(execute=True)
  File "/usr/local/miniconda/lib/python3.7/site-packages/nipype/pipeline/engine/nodes.py", line 1253, in _run_interface
    self.config['execution']['stop_on_first_crash'])))
  File "/usr/local/miniconda/lib/python3.7/site-packages/nipype/pipeline/engine/nodes.py", line 1128, in _collate_results
    for i, nresult, err in nodes:
  File "/usr/local/miniconda/lib/python3.7/site-packages/nipype/pipeline/engine/utils.py", line 99, in nodelist_runner
    result = node.run(updatehash=updatehash)
  File "/usr/local/miniconda/lib/python3.7/site-packages/nipype/pipeline/engine/nodes.py", line 473, in run
    result = self._run_interface(execute=True)
  File "/usr/local/miniconda/lib/python3.7/site-packages/nipype/pipeline/engine/nodes.py", line 557, in _run_interface
    return self._run_command(execute)
  File "/usr/local/miniconda/lib/python3.7/site-packages/nipype/pipeline/engine/nodes.py", line 637, in _run_command
    result = self._interface.run(cwd=outdir)
  File "/usr/local/miniconda/lib/python3.7/site-packages/nipype/interfaces/base/core.py", line 369, in run
    runtime = self._run_interface(runtime)
  File "/usr/local/miniconda/lib/python3.7/site-packages/niworkflows/interfaces/freesurfer.py", line 328, in _run_interface
    newpath=runtime.cwd)
  File "/usr/local/miniconda/lib/python3.7/site-packages/niworkflows/interfaces/freesurfer.py", line 463, in medial_wall_to_nan
    darray.data[medial] = np.nan
ValueError: assignment destination is read-only
"
Would you know how to fix it?
It looks like there was a modification of numpy, isn't it?

Thanks in advance for your help!
