#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Error: .env file not found at $ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

for cmd in curl jq awk sed tr date mkdir cp; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command not found: $cmd" >&2
    exit 1
  fi
done

BUSINESSES_FILE="${BUSINESSES_FILE:-$SCRIPT_DIR/businesses.json}"
OUTPUT_ROOT="${OUTPUT_ROOT:-$SCRIPT_DIR/audit_output}"
BASE_URL="${BASE_URL:-https://intg-bhs-orchestrator.sandbox.thryv.com}"
ENDPOINT_PATH="${ENDPOINT_PATH:-/enterprise/insite/audit}"
TRANSACTION_PREFIX="${TRANSACTION_PREFIX:-test}"
CORRELATION_PREFIX="${CORRELATION_PREFIX:-corr}"

if [[ -z "${TOKEN:-}" ]]; then
  echo "Error: TOKEN is empty." >&2
  exit 1
fi

if [[ ! -f "$BUSINESSES_FILE" ]]; then
  echo "Error: businesses file not found at $BUSINESSES_FILE" >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Usage:
  ./run_audits.sh                # run all businesses in businesses.json
  ./run_audits.sh <slug>         # run only one business by slug

Examples:
  ./run_audits.sh
  ./run_audits.sh crema-downtown
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mkdir -p "$OUTPUT_ROOT"

run_one() {
  local business_json="$1"

  local slug name city state address phone country_code url
  slug="$(jq -r '.slug' <<<"$business_json")"
  name="$(jq -r '.name' <<<"$business_json")"
  city="$(jq -r '.city' <<<"$business_json")"
  state="$(jq -r '.state' <<<"$business_json")"
  address="$(jq -r '.address' <<<"$business_json")"
  phone="$(jq -r '.phone' <<<"$business_json")"
  country_code="$(jq -r '.country_code' <<<"$business_json")"
  url="$(jq -r '.url' <<<"$business_json")"

  local run_ts transaction_id correlation_id
  run_ts="$(date +%Y%m%d_%H%M%S)"
  transaction_id="${TRANSACTION_PREFIX}-${slug}-${run_ts}"
  correlation_id="${CORRELATION_PREFIX}-${slug}-${run_ts}"

  local run_dir
  run_dir="${OUTPUT_ROOT}/${slug}/${run_ts}"
  mkdir -p "$run_dir"

  local request_file response_raw_file response_pretty_file response_headers_file metadata_file summary_file metrics_file
  request_file="${run_dir}/request.json"
  response_raw_file="${run_dir}/response_raw.json"
  response_pretty_file="${run_dir}/response_pretty.json"
  response_headers_file="${run_dir}/response_headers.txt"
  metadata_file="${run_dir}/metadata.json"
  summary_file="${run_dir}/summary.txt"
  metrics_file="${run_dir}/curl_metrics.txt"

  jq -n \
    --arg correlationId "$correlation_id" \
    --arg name "$name" \
    --arg city "$city" \
    --arg state "$state" \
    --arg address "$address" \
    --arg phone "$phone" \
    --arg countryCode "$country_code" \
    --arg url "$url" \
    '{
      customFields: {
        _correlationId: $correlationId
      },
      business: {
        name: $name,
        city: $city,
        state: $state,
        address: $address,
        phone: $phone,
        country_code: $countryCode,
        url: $url
      }
    }' > "$request_file"

  curl -sS \
    -X POST "${BASE_URL}${ENDPOINT_PATH}?transactionId=${transaction_id}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    --data @"$request_file" \
    -D "$response_headers_file" \
    -o "$response_raw_file" \
    -w "%{http_code}\n%{time_total}\n%{time_namelookup}\n%{time_connect}\n%{time_appconnect}\n%{time_starttransfer}\n%{size_download}\n" \
    > "$metrics_file"

  local http_status time_total time_namelookup time_connect time_appconnect time_starttransfer size_download
  http_status="$(sed -n '1p' "$metrics_file")"
  time_total="$(sed -n '2p' "$metrics_file")"
  time_namelookup="$(sed -n '3p' "$metrics_file")"
  time_connect="$(sed -n '4p' "$metrics_file")"
  time_appconnect="$(sed -n '5p' "$metrics_file")"
  time_starttransfer="$(sed -n '6p' "$metrics_file")"
  size_download="$(sed -n '7p' "$metrics_file")"

  local time_total_ms time_starttransfer_ms response_is_json
  time_total_ms="$(awk "BEGIN {printf \"%.0f\", ${time_total:-0} * 1000}")"
  time_starttransfer_ms="$(awk "BEGIN {printf \"%.0f\", ${time_starttransfer:-0} * 1000}")"

  if jq . "$response_raw_file" > "$response_pretty_file" 2>/dev/null; then
    response_is_json=true
  else
    cp "$response_raw_file" "$response_pretty_file"
    response_is_json=false
  fi

  jq -n \
    --arg slug "$slug" \
    --arg name "$name" \
    --arg city "$city" \
    --arg state "$state" \
    --arg address "$address" \
    --arg phone "$phone" \
    --arg country_code "$country_code" \
    --arg url "$url" \
    --arg run_ts "$run_ts" \
    --arg run_dir "$run_dir" \
    --arg endpoint "${BASE_URL}${ENDPOINT_PATH}" \
    --arg transaction_id "$transaction_id" \
    --arg correlation_id "$correlation_id" \
    --arg request_file "$request_file" \
    --arg response_raw_file "$response_raw_file" \
    --arg response_pretty_file "$response_pretty_file" \
    --arg response_headers_file "$response_headers_file" \
    --arg http_status "${http_status:-0}" \
    --arg time_total "${time_total:-0}" \
    --arg time_total_ms "${time_total_ms:-0}" \
    --arg time_namelookup "${time_namelookup:-0}" \
    --arg time_connect "${time_connect:-0}" \
    --arg time_appconnect "${time_appconnect:-0}" \
    --arg time_starttransfer "${time_starttransfer:-0}" \
    --arg time_starttransfer_ms "${time_starttransfer_ms:-0}" \
    --arg size_download "${size_download:-0}" \
    --argjson response_is_json "$response_is_json" \
    '{
      business: {
        slug: $slug,
        name: $name,
        city: $city,
        state: $state,
        address: $address,
        phone: $phone,
        country_code: $country_code,
        url: $url
      },
      request: {
        endpoint: $endpoint,
        transaction_id: $transaction_id,
        correlation_id: $correlation_id,
        request_file: $request_file
      },
      response: {
        raw_file: $response_raw_file,
        pretty_file: $response_pretty_file,
        headers_file: $response_headers_file,
        http_status: ($http_status | tonumber),
        is_json: $response_is_json
      },
      timing: {
        total_seconds: ($time_total | tonumber),
        total_ms: ($time_total_ms | tonumber),
        namelookup_seconds: ($time_namelookup | tonumber),
        connect_seconds: ($time_connect | tonumber),
        appconnect_seconds: ($time_appconnect | tonumber),
        starttransfer_seconds: ($time_starttransfer | tonumber),
        starttransfer_ms: ($time_starttransfer_ms | tonumber)
      },
      size_download_bytes: ($size_download | tonumber),
      run_timestamp: $run_ts,
      run_directory: $run_dir
    }' > "$metadata_file"

  cat > "$summary_file" <<EOF
Business:             $name
Slug:                 $slug
City/State:           $city, $state
Address:              $address
Phone:                $phone
Country Code:         $country_code
URL:                  $url

Transaction ID:       $transaction_id
Correlation ID:       $correlation_id
Endpoint:             ${BASE_URL}${ENDPOINT_PATH}

HTTP Status:          $http_status
Total Response Time:  ${time_total}s (${time_total_ms} ms)
Time to First Byte:   ${time_starttransfer}s (${time_starttransfer_ms} ms)
Downloaded Bytes:     ${size_download}
Response Valid JSON:  ${response_is_json}

Files:
  Request JSON:       $request_file
  Raw Response:       $response_raw_file
  Pretty Response:    $response_pretty_file
  Response Headers:   $response_headers_file
  Metadata JSON:      $metadata_file
  Summary TXT:        $summary_file
EOF

  echo
  echo "Finished: $name"
  echo "Output:   $run_dir"
  echo "Status:   $http_status"
  echo "Time:     ${time_total}s (${time_total_ms} ms)"
}

FILTER_SLUG="${1:-all}"

if [[ "$FILTER_SLUG" == "all" ]]; then
  while IFS= read -r business; do
    [[ -n "$business" ]] && run_one "$business"
  done < <(jq -c '.[]' "$BUSINESSES_FILE")
else
  MATCHES="$(jq -c --arg wanted "$FILTER_SLUG" '.[] | select(.slug == $wanted)' "$BUSINESSES_FILE")"

  if [[ -z "$MATCHES" ]]; then
    echo "Error: no business found with slug: $FILTER_SLUG" >&2
    echo "Available slugs:" >&2
    jq -r '.[].slug' "$BUSINESSES_FILE" >&2
    exit 1
  fi

  while IFS= read -r business; do
    [[ -n "$business" ]] && run_one "$business"
  done <<< "$MATCHES"
fi

echo
echo "All done. Results are under: $OUTPUT_ROOT"