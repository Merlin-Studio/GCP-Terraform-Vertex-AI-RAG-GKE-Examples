# Services on a shared GKE cluster with Terraform: Workload Identity, Gateway API, private Cloud SQL

Most GKE examples build a cluster. This one answers the question that comes
next: **how does a team land a service on a cluster it does not own, on a Shared
VPC it does not own?** This is the `storefront` application — the marketplace's
buyer-facing side.

```
internet -> services -> relational        gateway → service → private Cloud SQL
            services -> events            publishes what happened
            services -> cache             reads a Memorystore cache
```

## What gets built

**In the cluster** ([`manifests.yaml`](../../applications/3-app-storefront-prd/manifests.yaml)) — a namespace of its own and everything scoped to it:

| Kind | Why |
|---|---|
| `Namespace`, `ResourceQuota` | the team's slice of a cluster it shares |
| `ServiceAccount` | bound to a Google service account through **Workload Identity** — no keys |
| `Deployment`, `Service` | the workload |
| `Gateway`, `HTTPRoute`, `GCPBackendPolicy` | **Gateway API** front door, with the Cloud Armor policy attached |
| `NetworkPolicy` × 2 | **default-deny** in both directions, then exactly the paths the service needs |

**Around it** ([`main.tf`](../../applications/3-app-storefront-prd/main.tf)) — private Cloud SQL (PostgreSQL) with CMEK, a Memorystore instance, a Pub/Sub topic, a Secret Manager secret for the database credential, and the service account the pods run as.

The cluster itself is the foundation's: [`3-gke-prd`](../../applications/3-gke-prd). The application never declares it.

## Default-deny, first

```yaml
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: storefront-prd
spec:
  podSelector: {}
  policyTypes: [Ingress, Egress]
```

Everything is refused, then a second policy opens the gateway in and the
database, cache and Google APIs out.

## Why each grant exists

| Identity | Role | On | Because of |
|---|---|---|---|
| `storefront-services-prd` | `roles/cloudsql.client` | the database | `services -> relational` |
| `storefront-services-prd` | `roles/cloudsql.instanceUser` | the database | `services -> relational` |
| `storefront-services-prd` | `roles/secretmanager.secretAccessor` | the database secret | `services -> relational` |
| `storefront-services-prd` | `roles/pubsub.publisher` | the events topic | `services -> events` |
| `storefront-services-prd` | `roles/redis.viewer` | the cache | `services -> cache` |

Every role is on the resource, not the project. The database secret is an empty
container: its value is added out of band, so it never passes through a
specification, a bundle or a state file.

## Where it lands

The application belongs to the `shop` department, so its resources are created in
`shop-app-<env>-0` and `shop-dp-<env>-0` on the department's own subnet — while
the cluster stays shared. Department scoping does not fragment the platform.
The department itself is in [`departments/shop`](../../departments/shop).

## The stages

- [`3-app-storefront-dev`](../../applications/3-app-storefront-dev) · [`-stg`](../../applications/3-app-storefront-stg) · [`-prd`](../../applications/3-app-storefront-prd)
- [`3-app-storefront-delivery`](../../applications/3-app-storefront-delivery) — the delivery pipeline, with a `skaffold.example.yaml`
- Preflight: [`deploy/preflight-storefront-prd.sh`](../../applications/deploy/preflight-storefront-prd.sh)

## What is still yours

Application code, routes and handlers, runtime configuration, the database
schema and the message contents.

← [All four examples](../../README.md)
