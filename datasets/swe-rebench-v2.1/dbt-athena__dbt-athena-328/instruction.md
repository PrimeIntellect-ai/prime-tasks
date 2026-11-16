BatchDeletePartitions only supports up to 25 partitions per call
failing example model:

```

{{
    config(
            materialized='table',
            ha=true,
            partitioned_by=["partition_date"],
        )
}}

with
    partitions as (
        select sequence(current_date - interval '99' day, current_date, interval '1' day) as date_sequence
), sequence_exploded as (
select cast(single_date as date) as single_date
from partitions cross join unnest (date_sequence) as t(single_date)
), partitioned_table as (
        select
            1 as foo,
            single_date as partition_date
        from sequence_exploded
    )
select *
from partitioned_table
```

Error on second `dbt run` (with existing table):
```
An error occurred (ValidationException) when calling the BatchDeletePartition operation: 1 validation error detected: Value '[PartitionValueList(values=[2023-05-25]), PartitionValueList(values=[2023-03-10]), PartitionValueList(values=[2023-05-03]), PartitionValueList(values=[2023-05-19]), PartitionValueList(values=[2023-05-13]), PartitionValueList(values=[2023-04-11]), PartitionValueList(values=[2023-03-05]), PartitionValueList(values=[2023-03-28]), PartitionValueList(values=[2023-04-17]), PartitionValueList(values=[2023-05-18]), PartitionValueList(values=[2023-05-14]), PartitionValueList(values=[2023-03-29]), PartitionValueList(values=[2023-04-28]), PartitionValueList(values=[2023-04-05]), PartitionValueList(values=[2023-04-26]), PartitionValueList(values=[2023-...
...
...
[2023-03-22]), PartitionValueList(values=[2023-03-13]), PartitionValueList(values=[2023-05-08]), PartitionValueList(values=[2023-04-29]), PartitionValueList(values=[2023-05-23])]' at 'partitionsToDelete' failed to satisfy constraint: Member must have length less than or equal to 25
```

using latest dbt-athena version 163b3d5a71ec131d9e0a7c3888b6d23d05f51b02
