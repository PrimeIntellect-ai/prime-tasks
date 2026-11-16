fix(bloc_lint): only `*_bloc.dart` and `*_cubit.dart` are included in analysis
**Description**
The `bloc_lint` rules should apply to all bloc and cubit instances not just instances that are declared in files ending in `_bloc.dart` or `_cubit.dart`.
