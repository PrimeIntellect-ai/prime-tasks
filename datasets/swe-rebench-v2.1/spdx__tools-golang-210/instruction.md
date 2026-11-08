"filesAnalyzed" field is not working when set to false
Since [`filesAnalyzed`](https://spdx.github.io/spdx-spec/v2.3/package-information/#78-files-analyzed-field) is an optional field, it is set as omitempty. However, when `filesAnalyzed` is omitted, the default value is true. The purpose of the [IsFilesAnalyzedTagPresent](https://github.com/spdx/tools-golang/blob/main/spdx/v2/v2_3/package.go#L53) is to force the output of filesAnalyzed to false if it is the case (since golang default unmarshaling treats false as the default boolean empty value).

This unfortunately doesn't work and today, it is not possible to output a document that accurately sets `filesAnalyzed=false` for Package

Reported on behalf on Google internal user (Amit).
