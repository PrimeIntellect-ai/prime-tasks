Error: specutil: failed converting to *schema.Realm: sqlspec: table not found
Issue:

We are in process of developing a new database and I am trying out atlas as tool to apply schema changes made on local server over to a deployment postgres server.

I keep getting this error:

` Error: specutil: failed converting to *schema.Realm: sqlspec: table "geoid_models" not found `

It has nothing to do with that specific table. If I remove that table from schema, error just moves on to another table

` Error: specutil: failed converting to *schema.Realm: sqlspec: table "vertical_datums" not found `

### inspect command

` atlas schema inspect -u "postgres://postgres:<pass>@localhost:5432/<db>?sslmode=disable" > src/db/schema.hcl`

### apply command
`atlas schema apply -u "postgres://<user>:<pass>@<server>:5432/<db>" -f src/db/schema.hcl`

### schema.hcl
```hcl
table "file_formats" {
  schema = schema.public
  column "id" {
    null = false
    type = serial
  }
  column "code" {
    null = false
    type = character_varying
  }
  column "description" {
    null = false
    type = character_varying
  }
  column "data_type" {
    null = false
    type = character_varying
  }
  primary_key {
    columns = [column.id]
  }
}
table "geoid_models" {
  schema = schema.public
  column "id" {
    null = false
    type = integer
  }
  column "name" {
    null = false
    type = character_varying
  }
  column "sort_order" {
    null = false
    type = smallint
  }
  primary_key {
    columns = [column.id]
  }
}
table "job_statuses" {
  schema = schema.public
  column "id" {
    null = false
    type = serial
  }
  column "status" {
    null = false
    type = character_varying
  }
  primary_key {
    columns = [column.id]
  }
}
table "request_statuses" {
  schema = schema.public
  column "id" {
    null = false
    type = serial
  }
  column "status" {
    null = false
    type = character_varying
  }
  primary_key {
    columns = [column.id]
  }
}
table "spatial_ref_sys" {
  schema = schema.public
  column "srid" {
    null = false
    type = integer
  }
  column "auth_name" {
    null = true
    type = character_varying(256)
  }
  column "auth_srid" {
    null = true
    type = integer
  }
  column "srtext" {
    null = true
    type = character_varying(2048)
  }
  column "proj4text" {
    null = true
    type = character_varying(2048)
  }
  primary_key {
    columns = [column.srid]
  }
  check "spatial_ref_sys_srid_check" {
    expr = "((srid > 0) AND (srid <= 998999))"
  }
}
table "vertical_datums" {
  schema = schema.public
  column "id" {
    null = false
    type = integer
  }
  column "name" {
    null = false
    type = character_varying
  }
  column "native_name" {
    null = false
    type = character_varying
  }
  primary_key {
    columns = [column.id]
  }
}
table "image_fp" {
  schema = schema.spatial
  column "objectid" {
    null = false
    type = serial
  }
  column "geom" {
    null = true
    type = sql("geometry(geometry,4269)")
  }
  column "location" {
    null = true
    type = character_varying(254)
  }
  column "url" {
    null = true
    type = character_varying(254)
  }
  column "missionid" {
    null = true
    type = integer
  }
  column "azureblobname" {
    null = true
    type = character_varying(1000)
  }
  primary_key {
    columns = [column.objectid]
  }
  index "image_fp_geom_geom_idx" {
    columns = [column.geom]
    type    = GIST
  }
}
table "dem_jobs" {
  schema = schema.transactional
  column "id" {
    null = false
    type = bigserial
  }
  column "job_id" {
    null = false
    type = bigint
  }
  column "vertical_datum_id" {
    null = false
    type = integer
  }
  column "contour_interval" {
    null = true
    type = real
  }
  column "geoid_model_id" {
    null = true
    type = integer
  }
  primary_key {
    columns = [column.id]
  }
  foreign_key "geoid_models_fkey" {
    columns     = [column.geoid_model_id]
    ref_columns = [table.geoid_models.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
  foreign_key "jobs_fkey" {
    columns     = [column.job_id]
    ref_columns = [table.jobs.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
  foreign_key "vertical_datums_fkey" {
    columns     = [column.vertical_datum_id]
    ref_columns = [table.vertical_datums.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
}
table "imagery_jobs" {
  schema = schema.transactional
  column "id" {
    null = false
    type = bigserial
  }
  column "job_id" {
    null = false
    type = bigint
  }
  column "jpeg_quality" {
    null    = false
    type    = smallint
    default = 80
  }
  primary_key {
    columns = [column.id]
  }
  foreign_key "jobs_fkey" {
    columns     = [column.job_id]
    ref_columns = [table.jobs.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
}
table "job_outputs" {
  schema = schema.transactional
  column "id" {
    null = false
    type = bigserial
  }
  column "job_id" {
    null = false
    type = bigint
  }
  column "file_path" {
    null = true
    type = character_varying
  }
  column "cleanup_status" {
    null = true
    type = character_varying
  }
  primary_key {
    columns = [column.id]
  }
  foreign_key "jobs_fkey" {
    columns     = [column.job_id]
    ref_columns = [table.jobs.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
  index "job_id_unique" {
    unique  = true
    columns = [column.job_id]
    type    = BTREE
  }
}
table "jobs" {
  schema = schema.transactional
  column "id" {
    null = false
    type = bigserial
  }
  column "request_id" {
    null = true
    type = bigint
  }
  column "data_type" {
    null = false
    type = character_varying
  }
  column "progress" {
    null = true
    type = character_varying
  }
  column "processing_started_at" {
    null = true
    type = time
  }
  column "processing_finished_at" {
    null = true
    type = time
  }
  column "job_status_id" {
    null = false
    type = integer
  }
  column "created_at" {
    null = false
    type = time
  }
  column "updated_at" {
    null = false
    type = time
  }
  column "geom" {
    null = true
    type = polygon
  }
  column "horizontal_datum_id" {
    null = false
    type = integer
  }
  column "projection_id" {
    null = false
    type = integer
  }
  column "mission_id" {
    null = false
    type = integer
  }
  column "file_format_id" {
    null = false
    type = integer
  }
  primary_key {
    columns = [column.id]
  }
  foreign_key "file_formats_fkey" {
    columns     = [column.file_format_id]
    ref_columns = [table.file_formats.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
  foreign_key "job_statuses_fkey" {
    columns     = [column.job_status_id]
    ref_columns = [table.job_statuses.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
  foreign_key "requests_fkey" {
    columns     = [column.request_id]
    ref_columns = [table.requests.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
}
table "landcover_jobs" {
  schema = schema.transactional
  column "id" {
    null = false
    type = bigserial
  }
  column "job_id" {
    null = false
    type = bigint
  }
  primary_key {
    columns = [column.id]
  }
  foreign_key "jobs_fkey" {
    columns     = [column.job_id]
    ref_columns = [table.jobs.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
}
table "lidar_jobs" {
  schema = schema.transactional
  column "id" {
    null = false
    type = bigserial
  }
  column "job_id" {
    null = false
    type = bigint
  }
  column "bin_unit" {
    null = true
    type = sql("linear_unit")
  }
  column "bin_size" {
    null = true
    type = real
  }
  column "fill_gaps" {
    null = true
    type = boolean
  }
  column "contour_interval" {
    null = true
    type = real
  }
  column "create_single_contour" {
    null = true
    type = boolean
  }
  column "ancillary_data" {
    null = true
    type = sql("channels")
  }
  column "data_returns" {
    null = true
    type = sql("lidar_returns")
  }
  column "vertical_unit" {
    null = false
    type = sql("linear_unit")
  }
  column "classes" {
    null = false
    type = sql("smallint[]")
  }
  column "point_size_estimate" {
    null = true
    type = bigint
  }
  column "geoid_model" {
    null = false
    type = sql("geoid")
  }
  primary_key {
    columns = [column.id]
  }
  foreign_key "jobs_fkey" {
    columns     = [column.job_id]
    ref_columns = [table.jobs.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
}
table "requests" {
  schema = schema.transactional
  column "id" {
    null = false
    type = bigserial
  }
  column "confirmation_sent" {
    null    = true
    type    = boolean
    default = false
  }
  column "created_at" {
    null = false
    type = timestamp
  }
  column "updated_at" {
    null = false
    type = timestamp
  }
  column "user_id" {
    null = false
    type = bigint
  }
  column "request_status_id" {
    null = false
    type = integer
  }
  primary_key {
    columns = [column.id]
  }
  foreign_key "request_status_fk" {
    columns     = [column.request_status_id]
    ref_columns = [table.request_statuses.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
  foreign_key "users_fk" {
    columns     = [column.user_id]
    ref_columns = [table.users.column.id]
    on_update   = NO_ACTION
    on_delete   = NO_ACTION
  }
}
table "users" {
  schema = schema.transactional
  column "id" {
    null = false
    type = bigserial
  }
  column "email" {
    null = false
    type = character_varying
  }
  column "organization" {
    null = true
    type = character_varying
  }
  column "survey_optin" {
    null    = true
    type    = boolean
    default = false
  }
  primary_key {
    columns = [column.id]
  }
}
schema "public" {
}
schema "spatial" {
}
schema "transactional" {
}
```

### Additional contract requirements

- Add a function `QualifyReferencedTables(tableSpecs []*sqlspec.Table, realm *schema.Realm) error` in package `specutil` (import path `ariga.io/atlas/sql/internal/specutil`).
- Given the HCL table specifications and the full database schema, the function sets the `Qualifier` field of the `sqlspec.Table` that corresponds to a table referenced by a foreign key crossing a schema boundary, to the name of the schema that contains the referenced table. A table that is only referenced from within its own schema keeps an empty qualifier.
- The function returns an error when a schema name cannot be resolved.
