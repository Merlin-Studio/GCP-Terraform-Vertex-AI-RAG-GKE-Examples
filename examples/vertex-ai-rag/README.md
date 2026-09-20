# Retrieval-augmented generation (RAG) on Vertex AI Vector Search with Terraform

A production-shaped RAG service on Google Cloud: private, one identity per
service, customer-managed keys on the data, and the model behind a guardrail.
This is the `seller-assistant` application — it answers marketplace sellers'
questions from the policy corpus and from nothing else.

```
objects -> embeddings -> vectors          corpus bucket → embedding service → vector index
events  -> embeddings                     a new document triggers re-embedding
internet -> api -> vectors                a question finds its matching passages
            api -> llm                    and the model answers from those alone
```

## What gets built

| | Resource | Project |
|---|---|---|
| Corpus | Cloud Storage bucket, CMEK | `seller-dp-<env>-0` (data) |
| Embedding service | Cloud Run, own service account | `seller-app-<env>-0` |
| Vector store | **Vertex AI Vector Search** index + endpoint, CMEK | `seller-dp-<env>-0` (data) |
| Re-index trigger | Pub/Sub topic, CMEK | `seller-dp-<env>-0` (data) |
| Query API | Cloud Run behind an external Application Load Balancer + Cloud Armor | `seller-app-<env>-0` |
| Model guardrail | **Model Armor** template | `seller-app-<env>-0` |

Note where the data lives: the corpus and the index are in the department's
**data** project, not the application's. The services that read them are in the
app project and hold nothing, which is why they carry no customer-managed key.

## The Terraform that matters

The index — and the two settings you cannot change later:

```hcl
resource "google_vertex_ai_index" "seller-assistant-vectors-prd" {
  project = local.project_seller_dp_prd_0
  region  = "europe-west4"
  metadata {
    config {
      dimensions                  = 768
      approximate_neighbors_count = 150
      # Has to match what the embedding model was trained for, and cannot be
      # changed once the index is built.
      distance_measure_type = "COSINE_DISTANCE"
```

The guardrail in front of the model:

```hcl
resource "google_model_armor_template" "seller-assistant-llm-prd" {
  filter_config {
    # Personal data detected and de-identified before the model sees it.
    sdp_settings { basic_config { filter_enforcement = "ENABLED" } }
    # Injection and jailbreak screening.
```

## Why each grant exists

| Identity | Role | On | Because of |
|---|---|---|---|
| `seller-assistant-embedding-prd` | `roles/storage.objectViewer` | the corpus bucket | `objects -> embeddings` |
| `seller-assistant-embedding-prd` | `roles/aiplatform.user` | the vector index | `embeddings -> vectors` |
| `seller-assistant-embedding-prd` | `roles/pubsub.subscriber` | the events topic | `events -> embeddings` |
| `seller-assistant-embedding-prd` | `roles/pubsub.viewer` | the events topic | `events -> embeddings` |
| `seller-assistant-api-prd` | `roles/aiplatform.user` | the vector index | `api -> vectors` |
| `seller-assistant-api-prd` | `roles/aiplatform.user` | the model guardrail | `api -> llm` |

The query API cannot read the corpus bucket. It has no reason to, so it has no
grant.

## The stages

- [`3-app-seller-assistant-dev`](../../applications/3-app-seller-assistant-dev) · [`-stg`](../../applications/3-app-seller-assistant-stg) · [`-prd`](../../applications/3-app-seller-assistant-prd) — one Terraform root per environment
- [`3-app-seller-assistant-delivery`](../../applications/3-app-seller-assistant-delivery) — the delivery pipeline
- Preflight: [`deploy/preflight-seller-assistant-prd.sh`](../../applications/deploy/preflight-seller-assistant-prd.sh) checks projects, network, keys and your permissions before an apply

## What is still yours

Chunking strategy, the embedding model, the reindex policy, retrieval
evaluation, prompts and grounding, and the application code. The container
images are placeholders until your pipeline publishes one.

← [All four examples](../../README.md)
