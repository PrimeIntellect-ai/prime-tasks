No score calculated due to duplicated valued - but there are none
Hi,

I have just updated from v1.2.2 to the current stable one and have an issue when trying to get the scores using score() function.

Here is my minimal working example of my dataframe with 23 quantiles and two different models:

`structure(list(horizon = c(1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1), quantile_level = c(0.01,
0.025, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5,
0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 0.975, 0.99,
0.01, 0.025, 0.05, 0.1, 0.15, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45,
0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 0.975,
0.99), predicted = c(5.35315376022872, 9.12396909553366, 14.4327901263777,
24.489307525287, 34.9867996183794, 46.4553624063202, 59.2477457772545,
73.7116622553964, 90.2489556292532, 109.359461614548, 131.69234971995,
158.119413738478, 189.84966897597, 228.619898378085, 277.03089555638,
339.183084955727, 421.986502153105, 538.188654784847, 714.605201782047,
1020.92511089519, 1732.28799019992, 2740.22727819615, 4670.47092626978,
544.259535151695, 625.662788948147, 686.604659194983, 767.532158061512,
827.206800855391, 875.637600077042, 921.818067380725, 960.460781225578,
999.59596915051, 1037.78381581275, 1072.82981203823, 1107.33971380286,
1146.17643812765, 1181.99085636293, 1221.28760397391, 1263.65651351185,
1310.14138329667, 1362.9506492127, 1431.27163592678, 1508.44475750933,
1638.87879248664, 1751.3283853541, 1895.43764222727), model_type = c("Safinea_PRFM-2-2-log10",
"Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10",
"Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10",
"Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10",
"Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10",
"Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10",
"Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10",
"Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10", "Safinea_PRFM-2-2-log10",
"Safinea_PRFM-2-2-log10", "ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA",
"ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA",
"ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA",
"ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA",
"ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA", "ECDC-SARIMA"
), observed = c(1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7,
1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7,
1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7,
1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7,
1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7,
1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7, 1171.7
)), row.names = c(NA, -46L), class = "data.frame")`


Running `as_forecast_quantile(x)` works without any issues and it also looks ok. However, when I run score() on that, I get the following errors:

> 1: ! Computation for `wis` failed. Error: Assertion on 'quantile_level' failed: Contains duplicated values, position 24..
2: ! Computation for `overprediction` failed. Error: Assertion on 'quantile_level' failed: Contains duplicated values, position 24..
3: ! Computation for `underprediction` failed. Error: Assertion on 'quantile_level' failed: Contains duplicated values, position 24..
4: ! Computation for `dispersion` failed. Error: Assertion on 'quantile_level' failed: Contains duplicated values, position 24..
5: ! Computation for `bias` failed. Error: Assertion on 'quantile_level' failed: Contains duplicated values, position 24..
6: ! Computation for `interval_coverage_50` failed. Error: Assertion on 'quantile_level' failed: Contains duplicated values, position
  24..
7: ! Computation for `interval_coverage_90` failed. Error: Assertion on 'quantile_level' failed: Contains duplicated values, position
  24..
8: ! Computation for `ae_median` failed. Error: Assertion on 'quantile_level' failed: Contains duplicated values, position 24..

It seems the issue lies with duplication but I do not see it. Using `get_duplicate_forecasts()` also returns no duplications.


Am I missing something obvious?

Thanks for the help!
Rok

### Additional contract requirements

- When `as_forecast_quantile()` encounters quantile levels that differ only because of a small rounding error, it must issue a warning containing `rounding issue`.
