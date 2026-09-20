# Cloud Run with private Cloud SQL, Pub/Sub, Dataflow and BigQuery — with Terraform

Deploying a container to Cloud Run takes five minutes. **Connecting it privately
to Cloud SQL over a Shared VPC, behind a load balancer, with its events landing
in a warehouse it cannot reach back from, is the part nobody's five-minute
tutorial covers.** This is the `checkout` application — the marketplace's order
API.

```
internet -> api -> relational                       load balancer → Cloud Run → private Cloud SQL
            api -> events -> stream-processing -> warehouse
                                                    Pub/Sub → Dataflow → BigQuery
```

The API never waits for the analytics, and the analytics never reach back into
the order database. Those two sentences are the architecture.

## What gets built

| | Resource | Project |
|---|---|---|
| Front door | external Application Load Balancer + Cloud Armor | `shop-app-<env>-0` |
| Order API | **Cloud Run**, own service account | `shop-app-<env>-0` |
| Order database | **Cloud SQL** (PostgreSQL 15), private IP only, CMEK | `shop-dp-<env>-0` (data) |
| Credential | Secret Manager — an empty container, filled out of band | `shop-app-<env>-0`, beside the service that reads it |
| Order events | Pub/Sub topic, CMEK | `shop-dp-<env>-0` |
| Pipeline | **Dataflow** flex template, `PubSub_to_BigQuery_Flex`, private workers, own service account | `shop-dp-<env>-0` |
| Staging | Cloud Storage bucket for the pipeline, CMEK | `shop-dp-<env>-0` |
| Warehouse | **BigQuery** dataset, CMEK | `shop-dp-<env>-0` |

## The three settings that make it private

```hcl
# Cloud Run: reachable only through the load balancer, never directly.
ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

# Cloud Run: egress through the department's subnet on the Shared VPC,
# and only for private ranges — that is how it reaches the database.
vpc_access = { egress = "PRIVATE_RANGES_ONLY" }

# Dataflow: workers without public addresses.
ip_configuration = "WORKER_IP_PRIVATE"
```

The database has no public address at all; it answers on the foundation's
Private Service Access range.

## Why each grant exists

| Identity | Role | On | Because of |
|---|---|---|---|
| `checkout-api-prd` | `roles/cloudsql.client` | the database | `api -> relational` |
| `checkout-api-prd` | `roles/cloudsql.instanceUser` | the database | `api -> relational` |
| `checkout-api-prd` | `roles/secretmanager.secretAccessor` | the database secret | `api -> relational` |
| `checkout-api-prd` | `roles/pubsub.publisher` | the events topic | `api -> events` |
| `checkout-stream-processing-prd` | `roles/pubsub.subscriber` | the events topic | `events -> stream-processing` |
| `checkout-stream-processing-prd` | `roles/pubsub.viewer` | the events topic | `events -> stream-processing` |
| `checkout-stream-processing-prd` | `roles/dataflow.worker` | the data project | `events -> stream-processing` |
| `checkout-stream-processing-prd` | `roles/storage.objectAdmin` | the pipeline bucket | `events -> stream-processing` |
| `checkout-stream-processing-prd` | `roles/bigquery.dataEditor` | the warehouse dataset | `stream-processing -> warehouse` |
| `checkout-stream-processing-prd` | `roles/bigquery.jobUser` | the data project | `stream-processing -> warehouse` |

Two identities, and neither can do the other's job: the API can publish but not
read the warehouse; the pipeline can write the warehouse but has no grant on the
database. Two roles are on the project because Google offers no resource-scoped
form of them — and the table says which.

## The stages

- [`3-app-checkout-dev`](../../applications/3-app-checkout-dev) · [`-stg`](../../applications/3-app-checkout-stg) · [`-prd`](../../applications/3-app-checkout-prd)
- [`3-app-checkout-delivery`](../../applications/3-app-checkout-delivery) — the delivery pipeline
- Preflight: [`deploy/preflight-checkout-prd.sh`](../../applications/deploy/preflight-checkout-prd.sh)

## What is still yours

Application code, routes and handlers, the database schema, the message schema,
and the warehouse's table design.

← [All four examples](../../README.md)
