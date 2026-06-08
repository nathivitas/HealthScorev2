---

# HealthScorev2

Created by Naty Caraballo

---

# Overview

This repository provides a lightweight testing harness for validating and stress testing the HealthScore V2 audit endpoint.

The project supports:

- Running audits against the new endpoint
- Testing synchronous responses
- Testing asynchronous webhook callbacks
- Measuring API timing and latency
- Persisting audit responses locally
- Running stress and concurrency tests
- Capturing webhook payloads locally

This repository was designed specifically for integration validation and troubleshooting of the new HealthScore V2 audit flow.

---

# Architecture Goal

The purpose of this harness is to validate the complete audit lifecycle:

```text
Local Test Harness
        ↓
HealthScore V2 Endpoint
        ↓
Webhook Callback Delivery
        ↓
Local Webhook Receiver
```

The harness dynamically:

- Generates transaction IDs
- Generates correlation IDs
- Builds audit payloads
- Executes API requests
- Captures responses
- Stores audit metadata
- Receives async webhook callbacks

---

# Main Components

## Audit Runner

Main script:

```bash
scripts/run_audits-02.sh
```

Responsible for:

- Reading businesses.json
- Constructing request payloads
- Executing audit requests
- Storing responses
- Capturing timing metrics

---

## Webhook Receiver

Local webhook receiver:

```bash
scripts/webhook_receiver.py
```

Used for:

- Receiving async webhook callbacks
- Persisting webhook payloads locally
- Debugging asynchronous processing

---

## Business Dataset

Input data:

```bash
payloads/businesses.json
```

Contains sample businesses used during testing.

---

# Requirements

Required tools:

- bash
- curl
- jq
- python3

Optional:

- Cloudflare Tunnel
- ngrok

Recommended environment:

- macOS
- Linux

---

# JWT Token Setup

The audit endpoint requires a JWT token.

Generate the token from:

```text
https://stge-mc-product-fullfilment.staging.thryv.com/marketing-center/swagger-ui#/Health/get_marketing_center_api_health_jwt
```

Use:

```text
LOC1933CF2B
```

for the thryvId.

Copy the token value from the response and place it into:

```bash
TOKEN=
```

inside `.env`.

---

# Environment Setup

Copy the sample environment file:

```bash
cp .env.sample .env
```

Update the required values.

---

# Load Environment Variables

```bash
set -a
source .env
set +a
```

---

# Running Inline Audit Tests

This mode returns the response directly.

```bash
./scripts/run_audits-02.sh --no-webhook-response
```

---

# Running Single Business Audit

```bash
./scripts/run_audits-02.sh --slug crema-downtown --no-webhook-response
```

---

# Running Webhook Tests Locally

## Step 1 — Start Webhook Receiver

```bash
python3 scripts/webhook_receiver.py
```

Expected:

```text
Webhook receiver running on http://localhost:8080
```

---

## Step 2 — Expose Localhost Using Cloudflare Tunnel

Install Cloudflare Tunnel:

```bash
brew install cloudflared
```

Run tunnel:

```bash
cloudflared tunnel \
  --protocol http2 \
  --url http://localhost:8080
```

Cloudflare will generate a public HTTPS URL similar to:

```text
https://example.trycloudflare.com
```

---

## Step 3 — Update WEBHOOK_URL

In `.env`:

```bash
WEBHOOK_URL=https://example.trycloudflare.com
```

---

## Step 4 — Execute Webhook Audit

```bash
./scripts/run_audits-02.sh --webhook-url https://example.trycloudflare.com
```

---

# Output Structure

The scripts dynamically generate output directories during execution.

Generated artifacts include:

- request payloads
- raw responses
- formatted responses
- curl metrics
- webhook payloads
- timing metadata

Output folders are intentionally excluded from source control.

---

# Example Audit Payload

```json
{
  "customFields": {
    "_correlationId": "corr-001"
  },
  "business": {
    "name": "Acme Plumbing & Heating",
    "city": "Dallas",
    "state": "TX",
    "address": "123 Main St",
    "phone": "214-555-0192",
    "country_code": "US",
    "url": "https://www.acmeplumbing.com"
  }
}
```

---

# Example Endpoint

```text
POST /enterprise/insite/audit
```

---

# Common Troubleshooting

## Unauthorized

Verify:

- JWT token is valid
- Token has not expired
- Authorization header is correct

---

## Webhook Not Received

Verify:

- Cloudflare tunnel is active
- WEBHOOK_URL is reachable publicly
- Local receiver is running
- Port 8080 is available

---

## jq Errors

Install jq:

```bash
brew install jq
```

---

# Stress Testing

Stress testing scripts:

```bash
scripts/stress_sagemaker_hotfix.sh
```

These are used to validate:

- concurrency behavior
- webhook stability
- endpoint throughput
- response consistency

---

# Security Notes

This repository intentionally excludes:

- `.env`
- JWT tokens
- AWS credentials
- generated outputs

Never commit secrets to GitHub.

---

# Ownership

Created and maintained by Naty Caraballo.

Main audit runner script reference: :contentReference[oaicite:0]{index=0}