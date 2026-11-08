explain_predictions_ functions should return top_k features by magnitude of SHAP value
Currently, the explain_predictions_ functions accept a top_k_features argument. By design, this returns the features with the top_k highest and top_k smallest shap values for a total of 2 * top_k features.

The idea was to give users a sense of what drives a particular prediction up vs down but this approach can include some irrelevant information. For example, consider a prediction where every feature has a positive SHAP value but 10 features have really high Shap values and the smallest 5 have shap values close to 0. Passing top_k=5, would include the 5 features with near-zero shap values. It would be better to just return the 10 features with the highest shap value by magnitude.

FYI @kmax12

### Additional contract requirements

For each explanation produced by a single-prediction API or a multiple-prediction API, `top_k` (or the plural APIs' `top_k_features` parameter) is the maximum number of selected features: return that many features with the greatest absolute SHAP values, or all available features if fewer exist. Do not independently select positive and negative extremes. The example's statement that `top_k=5` returns 10 features conflicts with the stated parameter meaning; the result count is five (or fewer if fewer features are available).
