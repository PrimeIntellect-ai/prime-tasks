Unable to Disable Logging by Setting samplingRate to Zero
In certain scenarios, it is useful to completely suppress logging by setting the `samplingRate` to zero. However, the current code prevents this by taking the default value when `samplingRate` is set to zero, as shown in the following segment:

https://github.com/microsoft/ApplicationInsights-node.js/blob/main/src/shared/configuration/config.ts#L112

To address this, we need to modify the code to allow samplingRate to be set to zero without reverting to the default value. This change will provide greater flexibility in controlling logging behavior.
