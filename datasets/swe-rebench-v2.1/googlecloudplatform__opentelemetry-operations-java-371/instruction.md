Cloud Run Jobs are detected as gcp_compute_engine
Currently, workloads running as Cloud Run Jobs are being detected as GCP compute engine - this is because the resource detection does not support Cloud Run Jobs yet which leads to resource detection logic fall back to `gcp_compute_engine`.

Environment variables in a Cloud Run Job container differ from the environment variables set when the container is run as a Cloud Run Service.

Details around the differences between environment variables are documented [here](https://cloud.google.com/run/docs/container-contract#env-vars).

Update resource detection logic to support Cloud Run Job detection.

### Additional contract requirements

When a container's environment defines the `CLOUD_RUN_JOB` environment variable, the detected platform is Cloud Run Job rather than Compute Engine. The platform is reported as `GCPPlatformDetector.SupportedPlatform.GOOGLE_CLOUD_RUN_JOB`.

The detected platform exposes exactly five resource attributes:
- `serverless_compute_name` → the value of the `CLOUD_RUN_JOB` environment variable
- `gcr_job_execution_key` → the value of the `CLOUD_RUN_EXECUTION` environment variable
- `gcr_job_task_index` → the value of the `CLOUD_RUN_TASK_INDEX` environment variable
- `instance_id` → the instance ID from the GCP metadata service
- `cloud_region` → the region derived from the zone reported by the GCP metadata service

The detected platform's project ID is the project ID from the GCP metadata service.
