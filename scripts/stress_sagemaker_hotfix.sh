#!/usr/bin/env bash
set -euo pipefail

ENDPOINT="${SAGEMAKER_ENDPOINT:-stge-xgb-multilabel-inference-endpoint-v3hotfix}"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
AUDIT_DIR="${AUDIT_DIR:-./Insites}"
TOTAL_RUNS="${TOTAL_RUNS:-100}"

OUT_DIR="sagemaker_hotfix_stress_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUT_DIR/requests" "$OUT_DIR/raw" "$OUT_DIR/pretty" "$OUT_DIR/reports"

FILES=()
while IFS= read -r file; do
  FILES+=("$file")
done < <(
  find "$AUDIT_DIR" -maxdepth 1 -type f -name "*.json" \
    ! -name "request.json" \
    ! -name "response.json" \
    ! -name "response.pretty.json" \
    | sort
)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No JSON files found in $AUDIT_DIR"
  exit 1
fi

SUMMARY="$OUT_DIR/reports/summary.jsonl"
ERRORS="$OUT_DIR/reports/errors.log"
GROUPED="$OUT_DIR/reports/grouped_scores_by_file.json"
TSV="$OUT_DIR/reports/category_scores.tsv"

echo "Endpoint: $ENDPOINT"
echo "Region: $REGION"
echo "Audit dir: $AUDIT_DIR"
echo "Total runs: $TOTAL_RUNS"
echo "Files found: ${#FILES[@]}"
echo "Output dir: $OUT_DIR"
echo

for i in $(seq 1 "$TOTAL_RUNS"); do
  index=$(( (i - 1) % ${#FILES[@]} ))
  file="${FILES[$index]}"
  base="$(basename "$file" .json)"
  run_id="$(printf "%03d" "$i")"

  if ! jq empty "$file" >/dev/null 2>&1; then
    echo "Run $run_id | Skipping invalid JSON: $file" | tee -a "$ERRORS"
    continue
  fi

  report_id="$(jq -r '.report_id // .custom_fields.txn_id // .custom_fields.correlation_id // "'"$base"'"' "$file")"

  request_file="$OUT_DIR/requests/${run_id}_${base}_request.json"
  raw_response="$OUT_DIR/raw/${run_id}_${base}_response.raw.json"
  pretty_response="$OUT_DIR/pretty/${run_id}_${base}_response.pretty.json"

  jq -n \
    --arg rid "$report_id" \
    --slurpfile audit "$file" \
    '{report_id:$rid,audit_data:$audit[0]}' \
    > "$request_file"

  echo "Run $run_id/$TOTAL_RUNS | file=$base.json | report_id=$report_id"

  start_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')

  if aws sagemaker-runtime invoke-endpoint \
    --region "$REGION" \
    --endpoint-name "$ENDPOINT" \
    --content-type application/json \
    --body "fileb://$request_file" \
    "$raw_response" \
    >/dev/null 2>>"$ERRORS"; then

    end_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')
    duration_ms=$((end_ms - start_ms))

    if jq -e 'type == "string"' "$raw_response" >/dev/null 2>&1; then
      jq -r . "$raw_response" | jq > "$pretty_response"
    else
      jq > "$pretty_response" < "$raw_response"
    fi

    jq -nc \
      --arg run_id "$run_id" \
      --arg file "$file" \
      --arg report_id "$report_id" \
      --arg duration_ms "$duration_ms" \
      --slurpfile response "$pretty_response" \
      '{
        run_id: $run_id,
        file: $file,
        report_id: $report_id,
        duration_ms: ($duration_ms | tonumber),
        response_report_id: ($response[0].report_id // null),
        model_version: ($response[0].model_version // null),
        overall_score: ($response[0].overall_score // null),
        source: ($response[0].source // null),
        categories: (
          $response[0].categories // []
          | map({
              category: (.category // .label // null),
              category_score: (.category_score // .score // null)
            })
        ),
        status: "success"
      }' >> "$SUMMARY"

  else
    end_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')
    duration_ms=$((end_ms - start_ms))

    jq -nc \
      --arg run_id "$run_id" \
      --arg file "$file" \
      --arg report_id "$report_id" \
      --arg duration_ms "$duration_ms" \
      '{
        run_id: $run_id,
        file: $file,
        report_id: $report_id,
        duration_ms: ($duration_ms | tonumber),
        status: "failed"
      }' >> "$SUMMARY"

    echo "Run $run_id failed. See $ERRORS"
  fi
done

jq -s '
  group_by(.file)
  | map({
      file: .[0].file,
      total_runs: length,
      successful_runs: map(select(.status == "success")) | length,
      failed_runs: map(select(.status == "failed")) | length,
      runs: map({
        run_id,
        status,
        duration_ms,
        overall_score,
        source,
        categories
      })
    })
' "$SUMMARY" > "$GROUPED"

{
  echo -e "file\trun_id\tstatus\tduration_ms\toverall_score\tsource\tcategory\tcategory_score"
  jq -r '
    .file as $file
    | .run_id as $run
    | .status as $status
    | .duration_ms as $duration
    | (.overall_score // "") as $overall
    | (.source // "") as $source
    | if (.categories | type) == "array" and (.categories | length) > 0 then
        .categories[]
        | [$file, $run, $status, $duration, $overall, $source, (.category // ""), (.category_score // "")]
        | @tsv
      else
        [$file, $run, $status, $duration, $overall, $source, "", ""]
        | @tsv
      end
  ' "$SUMMARY"
} > "$TSV"

echo
echo "Done."
echo "Output directory: $OUT_DIR"
echo "Raw responses: $OUT_DIR/raw"
echo "Pretty responses: $OUT_DIR/pretty"
echo "Summary JSONL: $SUMMARY"
echo "Grouped report: $GROUPED"
echo "Category TSV: $TSV"
echo "Errors: $ERRORS"
