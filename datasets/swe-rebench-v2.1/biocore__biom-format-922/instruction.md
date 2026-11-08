Conversion from hdf5 to json fails on int64´s
`biom convert -i input_hdf5_data_biom.biom -o table_from_hdf5_json.biom  --to-json `
Fails with
`TypeError: Object of type int64 is not JSON serializable`
