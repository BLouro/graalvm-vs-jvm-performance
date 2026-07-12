#!/usr/bin/env bash
# Run from the repo root (where docker-compose.yaml lives).
set -euo pipefail

REPEATS=3
SAMPLE_INTERVAL=2 # seconds between docker stats samples
RESULTS_DIR="k6/results"
mkdir -p "${RESULTS_DIR}"

run() {
  local service=$1
  local port=$2
  local label=$3

  echo "== ${service}: restarting for a clean baseline =="
  docker compose stop "${service}" >/dev/null 2>&1 || true
  docker compose rm -f "${service}" >/dev/null 2>&1 || true
  docker compose up -d "${service}" >/dev/null

  until curl -sf "http://localhost:${port}/actuator/health" >/dev/null 2>&1; do
    sleep 0.1
  done

  echo "== ${service}: settling before load =="
  sleep 10

  local statsfile="${RESULTS_DIR}/mem-cpu-${label}.csv"
  ./scripts/sample-container-stats.sh "${statsfile}" "${SAMPLE_INTERVAL}" "${service}" &
  local sampler_pid=$!

  for i in $(seq 1 "${REPEATS}"); do
    echo "== ${service}: run ${i}/${REPEATS} =="
    docker run --rm -i \
      -e PORT="${port}" \
      -v "$(pwd)/${RESULTS_DIR}:/results" \
      grafana/k6 run --summary-export="/results/${label}-run${i}.json" - \
      < k6/stress.js | tee "${RESULTS_DIR}/${label}-run${i}.txt"
  done

  kill "${sampler_pid}" 2>/dev/null || true
  wait "${sampler_pid}" 2>/dev/null || true
  echo "== ${service}: container stats saved to ${statsfile} =="
}

run spring-boot-jvm 8080 jvm
run spring-boot-graalvm 8081 native

echo "Done. Per-run k6 results (txt + json) and continuous docker-stats CSVs are in ${RESULTS_DIR}/"
