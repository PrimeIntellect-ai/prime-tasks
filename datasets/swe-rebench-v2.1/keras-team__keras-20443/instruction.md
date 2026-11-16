UnicodeEncodeError when running keras.model.predict
The following problem occurs in keras version 3.1.1 (tensorflow version 2.16.1)
UnicodeEncodeError: 'charmap' codec can't encode characters in position 19-38: character maps to <undefined>

prediction = trained_nn_model.predict(last_sequence)
A bit more details:
  File "...\lib\site-packages\keras\src\utils\traceback_utils.py", line 122, in error_handler
    raise e.with_traceback(filtered_tb) from None
  File "...\.pyenv\pyenv-win\versions\3.10.5\lib\encodings\cp1252.py", line 20, in encode
    return codecs.charmap_encode(input,self.errors,encoding_table)[0]
UnicodeEncodeError: 'charmap' codec can't encode characters in position 19-38: character maps to <undefined>

(The positions varies when tried with different test data).
The code works ok with keras version 2.15.0 (tensorflow 2.15.0)
