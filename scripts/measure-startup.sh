#!/usr/bin/env bash
# Measures cold-start time and idle memory for each variant, run before any k6 load.
# Must be run from the repo root (where docker-compose.yaml lives).
set -euo pipefail

measure() {
  local service=$1
  local port=$2

  echo "== ${service} =="

  docker compose stop "${service}" >/dev/null 2>&1 || true
  docker compose rm -f "${service}" >/dev/null 2>&1 || true

  docker compose up -d "${service}" >/dev/null

  local waited=$SECONDS
  until curl -sf "http://localhost:${port}/actuator/health" >/dev/null 2>&1; do
    sleep 0.1
    if (( SECONDS - waited > 60 )); then
      echo "  timed out waiting for ${service} to become healthy"
      return 1
    fi
  done
  echo "  reachable after ~$((SECONDS - waited))s (poll granularity, not precise)"

  echo "  self-reported startup (authoritative number):"
  docker logs "${service}" 2>&1 | grep -m1 "Started" | sed 's/^/    /' || echo "    (no 'Started' line found in logs)"

  sleep 5 # let post-startup init (connection pool, JIT of early requests) settle

  echo "  idle memory / cpu (no load applied):"
  docker stats --no-stream --format "    {{.Name}}: CPU={{.CPUPerc}} MEM={{.MemUsage}}" "${service}"
  echo
}

measure spring-boot-jvm 8080
measure spring-boot-graalvm 8081
