# MySQL to Cloud SQL with Database Migration Service and Terraform — continuous replication over VPN

The database stays in the datacentre and a current copy lives in the cloud, kept
up to date by change data capture. Everything new is built against the copy, and
reporting never touches the system of record. This is the `inventory-replica`
application: the marketplace's old monolith still runs on MySQL in a colocation
facility, and will for another year.

```
onprem -> replicate -> relational         MySQL in the colo → DMS → Cloud SQL for MySQL
schedule -> job -> relational             a nightly job reads the replica
            job -> warehouse              and writes what it found to BigQuery
```

## What gets built

| | Resource | Project |
|---|---|---|
| Source profile | **Database Migration Service** connection profile for the on-premises MySQL | `seller-dp-prd-0` (data) |
| Replica | **Cloud SQL for MySQL 8.0**, private IP only, CMEK | `seller-dp-prd-0` |
| Replication | DMS migration job, `CONTINUOUS` | `seller-dp-prd-0` |
| Schedule | Cloud Scheduler, own service account | `seller-app-prd-0` |
| Job | Cloud Run job, own service account | `seller-app-prd-0` |
| Warehouse | BigQuery dataset, CMEK | `seller-dp-prd-0` |
| Credential | Secret Manager — an empty container, filled out of band | `seller-app-prd-0` |

## Four things this gets right that a first attempt gets wrong

**The destination engine is not a question.** You say what the source is; the
replica's engine follows from it. From [`CONFORMANCE.md`](../../applications/CONFORMANCE.md),
which records where every setting came from:

| Setting | Value | Source |
|---|---|---|
| `source_kind` | `mysql` | your answer, on the Applications page |
| `engine` | `mysql` | not asked: `inventory-replica-replicate-prd` replicates a mysql source into this instance, and Database Migration Service keeps a continuous copy only between two databases of the same engine |

Asked as two questions, the answers can disagree — a MySQL source pointed at a
PostgreSQL instance — and nothing downstream notices until the job fails.

**Continuous, not one-time.**

```hcl
# Copy what is already there, then follow changes. The one-time mode is a
# migration: it copies once and stops, which reads as a working replica
# until someone queries a row that changed afterwards.
type = "CONTINUOUS"
```

**One instance, not two.** The destination profile points at the instance this
stage creates — the one the application reads:

```hcl
# The destination is inventory-replica-relational-prd, the instance this stage
# creates and the application reads -- not a second instance Database Migration
# Service creates beside it. A `cloudsql { settings }` profile makes the
# service create its own, so the replica and the database the application
# queried were two instances and the application never saw a replicated row.
mysql { cloud_sql_id = module.sql-inventory-replica-relational-prd.name }
```

**Backups, while replicating.** A destination under replication is a read replica
of the source; Database Migration Service demotes it and manages its backups. A
variable says so to the instance, which would otherwise re-enable them on the
next apply and break the replica. Set it to `false` after promoting.

The order of operations is scripted:
[`deploy/replicate-inventory-replica-replicate-prd.sh`](../../applications/deploy/replicate-inventory-replica-replicate-prd.sh)
— `demote --confirm` once after the apply (it refuses if the destination already
holds databases of its own), then `start`.

## Production only, and why

This application needs a path to the datacentre, and only the production network
has the VPN. So there is no `dev` or `stg` stage, and the bundle says so itself,
in [`VALIDATION_WARNINGS.md`](../../applications/VALIDATION_WARNINGS.md):

> Application 'inventory-replica' is generated for prd only, not dev, stg:
> `vpc-shared-dev` has no path to the landing zone's private-network link.

An application is generated where the foundation can host it and nowhere else.
Add a VPN gateway to the non-production network in the foundation, regenerate,
and the other environments become available.

## Why each grant exists

| Identity | Role | On | Because of |
|---|---|---|---|
| `inventory-replica-replicat-prd` | `roles/cloudsql.client` | the replica | `replicate -> relational` |
| `inventory-replica-schedule-prd` | `roles/run.invoker` | the job | `schedule -> job` |
| `inventory-replica-job-prd` | `roles/cloudsql.client` | the replica | `job -> relational` |
| `inventory-replica-job-prd` | `roles/cloudsql.instanceUser` | the replica | `job -> relational` |
| `inventory-replica-job-prd` | `roles/secretmanager.secretAccessor` | the database secret | `job -> relational` |
| `inventory-replica-job-prd` | `roles/bigquery.dataEditor` | the warehouse dataset | `job -> warehouse` |
| `inventory-replica-job-prd` | `roles/bigquery.jobUser` | the data project | `job -> warehouse` |

The scheduler can start the job and do nothing else.

## The stages

- [`3-app-inventory-replica-prd`](../../applications/3-app-inventory-replica-prd)
- [`3-app-inventory-replica-delivery`](../../applications/3-app-inventory-replica-delivery) — the delivery pipeline
- Preflight: [`deploy/preflight-inventory-replica-prd.sh`](../../applications/deploy/preflight-inventory-replica-prd.sh)
- The VPN it depends on: [`foundation/networking`](../../foundation/networking)

## What is still yours

The source database's replication user and binary-log settings, the source host
and credentials (variables, never in the bundle), the job's code, and the
warehouse's table design.

← [All four examples](../../README.md)
