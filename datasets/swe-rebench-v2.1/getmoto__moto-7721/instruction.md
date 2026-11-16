S3: Configure the MaxKeys limit (list_objects/list_objects_v2) using an env variable
### Discussed in https://github.com/getmoto/moto/discussions/7696

<div type='discussions-op-text'>

<sup>Originally posted by **raphael-boegel-pcg** May 15, 2024</sup>
Is there anyway to overwrite specific parameters?
For example I want to to overwrite **MaxKeys** of list_objects_v2 (s3).</div>

### Additional contract requirements

- The environment variable used to configure the MaxKeys limit is named `MOTO_S3_DEFAULT_MAX_KEYS`.
