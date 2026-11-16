Serialized Composite Model Fails with XGBoost
I am having an issue with a serialized MLJ pipeline that includes an XGBoostClassifier - when trying to run predict  on the loaded model, I get the following error:
```
┌ Error: Failed to apply the operation `predict` to the machine machine(:xg_boost_classifier, …), which receives it's data arguments from one or more nodes in a learning network. Possibly, one of these nodes is delivering data that is incompatible with the machine's model.
│ Model (xg_boost_classifier):
│ input_scitype = Unknown
│ target_scitype =Unknown
│ output_scitype =Unknown
│
│ Incoming data:
│ arg of predict	scitype
│ -------------------------------------------
│ Node @103	Table{AbstractVector{Continuous}}
│
│ Learning network sources:
│ source	scitype
│ -------------------------------------------
│ Source @253	Nothing
│ Source @396	Nothing
└ @ MLJBase ~/.julia/packages/MLJBase/0rn2V/src/composition/learning_networks/nodes.jl:153
ERROR: XGBoostError: (caller: XGBoosterPredictFromDMatrix)
[00:01:27] /workspace/srcdir/xgboost/src/c_api/c_api.cc:913: Booster has not been initialized or has already been disposed.
Stack trace:
  [bt] (0) 1   libxgboost.dylib                    0x000000028780cc4c dmlc::LogMessageFatal::~LogMessageFatal() + 124
  [bt] (1) 2   libxgboost.dylib                    0x0000000287827614 XGBoosterPredictFromDMatrix + 116
  [bt] (2) 3   ???                                 0x00000002a858c0c8 0x0 + 11414323400
  [bt] (3) 4   ???                                 0x00000002a8404194 0x0 + 11412717972
  [bt] (4) 5   libjulia-internal.1.9.dylib         0x00000001048cdacc do_apply + 744
  [bt] (5) 6   ???                                 0x00000002a802c1a0 0x0 + 11408687520
  [bt] (6) 7   ???                                 0x00000002a79c40d8 0x0 + 11401969880
  [bt] (7) 8   ???                                 0x00000002a78e40d4 0x0 + 11401052372
  [bt] (8) 9   libjulia-internal.1.9.dylib         0x00000001048da53c do_call + 188
```

I've noted this on both Julia 1.8.5 and Julia 1.9.2 using up-to-date libraries for MLJ and XGBoost (which I believe recently updated to a version 2.0.0).  I also have noted that recently, the `MLJXGBoostInterface` library changed the way they serialize the XGBoost models.

### Additional contract requirements

- `MLJBase.serializable(mach::Machine, model=mach.model; verbosity=1)` returns a serializable copy of a trained machine. The optional `model` argument supplies the concrete model used to serialize the machine's fit result, so that a machine whose own `model` is a symbolic placeholder can be serialized using the corresponding concrete model.
- `MLJBase.restore!(mach::Machine, model=mach.model)` restores a machine that was previously made serializable, using the supplied concrete `model` to re-instantiate its fit result, and sets the machine's state to `1`.
- Serializing and restoring a composite model (a pipeline) that contains a sub-model with a non-persistent fit result must yield a machine that can be used again for prediction or transformation.
