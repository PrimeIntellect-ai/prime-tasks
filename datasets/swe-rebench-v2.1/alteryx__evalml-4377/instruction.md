Multiseries prediction interval labels includes target name twice
When generating the prediction interval labels for multiseries pipelines with STL decomposers, a KeyError is generated. This is due to the function trying to find a key that includes the target name twice (e.g. {{target|target|series_a}} instead of {{target|series_a}}).
