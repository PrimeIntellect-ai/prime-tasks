drop_duplicate_features with huge datasets
When running drop_duplicate_features() with a huge dataset (More that 60K features) it lasts forever (36 hours and couting), while simple code:

       # Remove duplicated features
        duplicated_feat = []
        for i in range(0, len(X_train.columns)):
            # if i % 10 == 0:  # this helps me understand how the loop is going
            #     print(i)

            col_1 = X_train.columns[i]

            for col_2 in X_train.columns[i + 1:]:
                if X_train[col_1].equals(X_train[col_2]):
                    duplicated_feat.append(col_2)

Took half an hour to finish. Please check.

### Additional contract requirements

- Duplicate detection compares the values stored in each column, not their dtypes. Two columns are duplicates when they hold the same values for every observation, even if their dtypes differ; for example, an integer column and a float column containing the same numbers are duplicates.
- The transformer must remain efficient when the dataset contains a very large number of features. In particular, `fit_transform` must process a DataFrame with 1000 columns in under 1 second.
