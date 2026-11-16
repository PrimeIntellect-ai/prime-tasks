Incorrect `file-name-heading` behaviour
Problem: linting inserts a file title incorrectly.

Steps to reproduce:

1. Create a note with the following content

    ```
    Text 1

    ---

    Text 2

    ```

2. Apply `file-name-heading`  linting rule
3. Expected result

    ```
    # Title

    Text 1

    ---

    Text 2

    ```

4. Actual (incorrect) result

    ```

    Text 1

    ---
    # Title

    Text 2

    ```

I believe this case should be added as an exception for documents with no YAML variables.
