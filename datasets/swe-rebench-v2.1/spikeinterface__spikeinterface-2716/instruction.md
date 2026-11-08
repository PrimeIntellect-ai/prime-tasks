Unable to open kilosort4 results with phy
Dear,

I'm using `spikeinterface==0.100.5` and `kilosort4== .4.0.3`, on 64 channel 6 shanks probe. The phy output is works perfectly with the  `ironclust ` generated results.

However, I have encountered some issues when open the kilosort4 phy output folder. And I saw there are some silimer reports, and I tried the following things:
1. Before waveform extraction `sorting.remove_empty_units()` and `sc.remove_excess_spikes(sorting_no_empty,rec_corrected1)`
2. Set `sparse=True` or `sparse=False` or `sparse=True, method="by_property",by_property="group"` in the `si.extract_waveforms()`
3. `sparsity=None` or `sparsity=True` in the `sexp.export_to_phy()`
None of above was works, and the phy is giving me the error message as below. I'm wondering if there any solution or any parameter I can adjust?

Error message:
```bash
19:51:55.272 [E] __init__:62          An error has occurred (AssertionError):
Traceback (most recent call last):
  File "<frozen runpy>", line 198, in _run_module_as_main
  File "<frozen runpy>", line 88, in _run_code
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Scripts\phy.exe\__main__.py", line 7, in <module>
    sys.exit(phycli())
             ^^^^^^^^
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\click\core.py", line 1157, in __call__
    return self.main(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\click\core.py", line 1078, in main
    rv = self.invoke(ctx)
         ^^^^^^^^^^^^^^^^
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\click\core.py", line 1688, in invoke
    return _process_result(sub_ctx.command.invoke(sub_ctx))
                           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\click\core.py", line 1434, in invoke
    return ctx.invoke(self.callback, **ctx.params)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\click\core.py", line 783, in invoke
    return __callback(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\click\decorators.py", line 33, in new_func
    return f(get_current_context(), *args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\phy\apps\__init__.py", line 159, in cli_template_gui
    template_gui(params_path, **kwargs)
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\phy\apps\template\gui.py", line 209, in template_gui
    model = load_model(params_path)
            ^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\phylib\io\model.py", line 1433, in load_model
    return TemplateModel(**get_template_params(params_path))
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\phylib\io\model.py", line 339, in __init__
    self._load_data()
  File "C:\Users\sachur\AppData\Local\anaconda3\envs\phy2\Lib\site-packages\phylib\io\model.py", line 358, in _load_data
    assert self.amplitudes.shape == (ns,)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
AssertionError

QWidget: Must construct a QApplication before a QWidget
```

### Additional contract requirements

The concrete fix required by this task is in `spikeinterface.curation.remove_excess_spikes`.
Besides removing spike times that are greater than or equal to the recording length (excess
spikes), `remove_excess_spikes(sorting, recording)` must also remove spike times that are
negative (less than 0). After the call, every spike time returned by the resulting sorting
must lie within `[0, num_samples)` for its segment, and the resulting sorting must keep the
same number of segments and the same unit ids as the input sorting.
