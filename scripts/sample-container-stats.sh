#!/usr/bin/env bash
# Samples real container memory/CPU straight from the Docker Engine API (the same data
# `docker stats` shows) at a fixed interval, for the given container(s). Each sample is:
#   1. appended as a CSV row (offline record), and
#   2. pushed to the Prometheus Pushgateway (http://localhost:9091), so it shows up live
#      in Grafana - this is what feeds the "Container CPU/Memory" panels, working around
#      cAdvisor not being able to see individual containers on Docker Desktop for Mac.
#
# Runs until killed (SIGTERM/SIGINT) - meant to be started in the background around a load test.
#
# Usage: sample-container-stats.sh <outfile.csv> <interval_seconds> <container>...
set -euo pipefail

OUTFILE=$1
INTERVAL=$2
shift 2
CONTAINERS=("$@")

PUSHGATEWAY_URL="http://localhost:9091"
DOCKER_SOCK="/var/run/docker.sock"

echo "timestamp,container,cpu_percent,mem_usage_bytes,mem_limit_bytes" > "${OUTFILE}"

trap 'exit 0' TERM INT

while true; do
  ts=$(date +%s)
  for container in "${CONTAINERS[@]}"; do
    stats_json=$(curl -s --unix-socket "${DOCKER_SOCK}" "http://localhost/containers/${container}/stats?stream=false" || true)
    [ -z "${stats_json}" ] && continue

    read -r mem_usage mem_limit cpu_percent < <(echo "${stats_json}" | jq -r '
      (.cpu_stats.cpu_usage.total_usage - .precpu_stats.cpu_usage.total_usage) as $cpu_delta |
      (.cpu_stats.system_cpu_usage - .precpu_stats.system_cpu_usage) as $sys_delta |
      (.cpu_stats.online_cpus // (.cpu_stats.cpu_usage.percpu_usage | length)) as $ncpu |
      (if $sys_delta > 0 and $cpu_delta > 0 then ($cpu_delta / $sys_delta) * $ncpu * 100 else 0 end) as $cpu_pct |
      "\(.memory_stats.usage) \(.memory_stats.limit) \($cpu_pct)"
    ')

    echo "${ts},${container},${cpu_percent},${mem_usage},${mem_limit}" >> "${OUTFILE}"

    cat <<EOF | curl -s --data-binary @- "${PUSHGATEWAY_URL}/metrics/job/docker-stats/instance/${container}" >/dev/null
# TYPE docker_stats_mem_usage_bytes gauge
docker_stats_mem_usage_bytes ${mem_usage}
# TYPE docker_stats_mem_limit_bytes gauge
docker_stats_mem_limit_bytes ${mem_limit}
# TYPE docker_stats_cpu_percent gauge
docker_stats_cpu_percent ${cpu_percent}
EOF
  done
  sleep "${INTERVAL}"
done
