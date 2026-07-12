# graalvm-vs-jvm-performance

## Goal

Two identical Spring Boot apps — a simple CRUD over a `books` table in Postgres —
one running on a regular JVM, the other compiled to a native binary with GraalVM.
Both are put under the same k6 load test, at the same container resource limits,
so their CPU and memory behavior can be compared directly: cold-start time, idle
memory, and steady-state resource usage under sustained load.

## Stack

- **spring-boot-jvm** / **spring-boot-graalvm** — the two app variants (port 8080 / 8081)
- **postgres** — shared database
- **k6** — load generator
- **Prometheus + Grafana** — metrics and dashboards
- **Pushgateway** — lets ad-hoc container-stats samples show up live in Grafana
  (works around cAdvisor not being able to see individual containers on Docker
  Desktop for Mac — see [Known limitations](#known-limitations))

## How to run

```bash
docker compose up -d            # infra: both apps, postgres, prometheus, grafana, cadvisor, pushgateway
./scripts/measure-startup.sh    # cold-start time + idle memory, before any load
./k6/run-test-.sh                # 3 repetitions of sustained load, per variant (~35-40 min total)
```

While `run-test-.sh` is running, open Grafana at `http://localhost:3000`
(dashboard "JVM vs GraalVM Native - CPU & Memory") to watch CPU/memory live.

`run-test-.sh` restarts each app fresh before its own run (no carryover state
between variants), then for each one: starts a container-stats sampler in the
background, runs k6 three times (30s warm-up + 5min sustained load + 15s
ramp-down each), then stops the sampler.

## How to analyze the results

Everything lands in `k6/results/` (gitignored — it's generated output, regenerated
every run):

| File | Contents | What to look at |
|---|---|---|
| `<label>-run<N>.json` | Structured k6 summary per repetition | `metrics.http_req_duration.avg` / `p(90)` / `p(95)`, `metrics.http_reqs.rate` (throughput), `metrics.http_req_failed.rate` (should be 0) |
| `<label>-run<N>.txt` | Same run, human-readable console output | Quick sanity check without parsing JSON |
| `mem-cpu-<label>.csv` | Real container memory/CPU sampled every 2s (via the Docker API), covering all 3 repetitions | `mem_usage_bytes` and `cpu_percent` over time — this is the most trustworthy, apples-to-apples resource number (see limitations below) |

**Suggested workflow:**
1. Compare the 3 `run<N>.json` files within the same variant first. Latency/throughput
   should be similar across repetitions — if they vary wildly, that's noise (JIT
   warmup differences, host scheduling jitter, GC pauses), not a real signal, and
   you should run more repetitions before trusting the numbers.
2. Once each variant's own repetitions look consistent, compare JVM vs native:
   throughput and latency from the JSON files, memory/CPU from the CSV files
   (compute mean/median/max per container).
3. Cross-check with Grafana while a run is happening: "Process CPU Usage" and "JVM
   Memory Used" panels are always live (scraped continuously); "Container CPU/Memory
   Usage" panels only have fresh data while `sample-container-stats.sh` is actually
   running (they hold the last pushed value indefinitely otherwise — don't read them
   outside of a `run-test-.sh` / `measure-startup.sh` window).
4. Don't skip `measure-startup.sh` — cold-start time and idle memory are where
   native's advantage is usually most visible, and the k6 load test alone won't
   capture it.

## Known limitations

- **Different GC, not just different runtime.** JVM 17 uses G1 by default. GraalVM
  Community Edition (used here) only supports Serial GC in native-image — G1 for
  native-image requires the non-free Oracle GraalVM. So results reflect "JVM+G1" vs
  "Native+Serial GC", not the runtime in isolation from the GC algorithm.
- **The "JVM Memory Used" Grafana panel isn't a perfectly symmetric comparison.**
  `jvm_memory_used_bytes` sums 7 pools on the JVM side (heap + Metaspace + Code Cache
  + Compressed Class Space) but only 3 on native (eden/old/survivor) — Substrate VM
  doesn't have the same Metaspace/Code Cache concepts. The "Container CPU/Memory
  Usage" panels (whole-container memory, seen from outside) are the more correct
  number for a direct comparison.
- **cAdvisor doesn't report per-container metrics on Docker Desktop for Mac** — a
  known limitation of that virtualization setup, not a config error. That's why
  "Container CPU/Memory Usage" is fed by the Pushgateway (via
  `sample-container-stats.sh`) instead.
- **The Pushgateway holds the last pushed value indefinitely**, even after
  `sample-container-stats.sh` stops — the "Container CPU/Memory Usage" panels will
  show a flat, stale line outside the windows where the sampler was actually
  running, rather than going empty. Only trust those panels during/right after a
  `run-test-.sh` or `measure-startup.sh`.
