Time Series estimators fail when y_holdout.index is reset
Repro:
```
target = "#Passengers"
time_index = "Month"
data = pd.read_csv(f"~/Downloads/AirPassengers.csv")
X = data.drop(target, axis=1)
y = data[target]

problem_configuration = {
    "max_delay": 52,
    "gap": 0,
    "forecast_horizon": 5,
    "time_index": time_index,
}

es = EntitySet()
es.add_dataframe(dataframe_name="X", dataframe=X, index="id", make_index=False)
features = dfs(
    entityset=es,
    target_dataframe_name="X",
    max_depth=1,
    features_only=True,
)
features.append(Feature(es["X"].ww[time_index]))
feature_matrix = calculate_feature_matrix(entityset=es, features=features)
feature_matrix.ww[f"target_delay_{start_delay}"] = y.shift(6)
feature_matrix_train, feature_matrix_holdout, y_train, y_holdout = split_data(
    feature_matrix, y, problem_type="time series regression"
)

automl_exclude = AutoMLSearch(
    feature_matrix_train,
    y_train,
    problem_type=problem_type,
    problem_configuration=problem_configuration,
    optimize_thresholds=False,
    exclude_featurizers=["DatetimeFeaturizer", "TimeSeriesFeaturizer"],
)
automl_exclude.search(interactive_plot=False)

# ARIMA with STL - working as expected
ex_pipeline = automl_exclude.get_pipeline(3)
ex_pipeline.fit(feature_matrix_train, y_train)
graph_prediction_vs_actual_over_time(
    ex_pipeline,
    feature_matrix_holdout,
    y_holdout,
    feature_matrix_train,
    y_train,
    feature_matrix_holdout[time_index],
)
```
![newplot (3)](https://user-images.githubusercontent.com/60074782/234375853-6eec1814-2df2-424a-b59b-d0516a336561.png)
```
# Breaking ARIMA with STL
y_reset_holdout = y_holdout.reset_index(drop=True)
graph_prediction_vs_actual_over_time(
    ex_pipeline,
    feature_matrix_holdout,
    y_reset_holdout,
    feature_matrix_train,
    y_train,
    feature_matrix_holdout[time_index],
)
```
![newplot (4)](https://user-images.githubusercontent.com/60074782/234376097-582c3b51-030b-4870-8ab3-f906e9321061.png)
