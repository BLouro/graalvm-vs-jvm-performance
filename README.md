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
- **Pushgateway** — lets container-stats samples (memory/CPU straight from the
  Docker API) show up live in Grafana; cAdvisor was tried for this first but
  doesn't see individual containers on Docker Desktop for Mac, so it was dropped

## How to run

```bash
docker compose up -d            # infra: both apps, postgres, prometheus, grafana, pushgateway
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

## Example results

From one clean local run (MacBook, Docker Desktop, 1 CPU / 512MB per app container,
10 VUs, 70% GET / 30% POST). Of the 6 repetitions (3 per variant), one JVM run was
thrown out because the Mac went to sleep mid-test (k6 reported 24m28s of real time
for what should've been a 5m45s run) — numbers below are the 2 remaining clean JVM
runs and all 3 clean native runs. Treat this as one example data point, not a
universal verdict — see [Known limitations](#known-limitations) before drawing
conclusions from it.

**Throughput & latency** (`k6/results/<label>-run<N>.json`):

| | Requests/s | Avg latency | p90 | p95 | Failed |
|---|---|---|---|---|---|
| JVM | 85.3 | 6.5ms | 8.6ms | 9.3ms | 0.000% |
| Native | 84.2 | 7.2ms | 9.4ms | 10.2ms | 0.002% |

Throughput is basically identical — expected, since at 10 VUs with a 0.1s sleep per
iteration, the load generator itself is the bottleneck, not the app. Latency is
close too, with the JVM slightly ahead (sub-millisecond difference) once warmed up.

**Container memory & CPU** (`k6/results/mem-cpu-<label>.csv`, sampled every 2s across all 3 repetitions):

| | Mem mean | Mem median | Mem max | CPU mean | CPU median | CPU max |
|---|---|---|---|---|---|---|
| JVM | 309.7 MiB | 312.0 MiB | 314.7 MiB | 12.1% | 9.4% | **87.9%** |
| Native | 85.0 MiB | 91.3 MiB | 130.5 MiB | 12.8% | 13.3% | 20.4% |

This is where the two variants actually diverge:
- **Memory:** native used roughly a third of the JVM's footprint, consistently
  (min 32.9 MiB / max 130.5 MiB vs. the JVM's tight 270.8-314.7 MiB band).
- **CPU shape, not just average:** mean CPU is similar, but the JVM has a max of
  88% against native's 20% — the JVM has occasional sharp spikes (JIT compilation,
  G1 GC pauses), while native stays flat (Serial GC, no JIT warm-up). Same average
  load, very different variance.

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
- **The Pushgateway holds the last pushed value indefinitely**, even after
  `sample-container-stats.sh` stops — the "Container CPU/Memory Usage" panels will
  show a flat, stale line outside the windows where the sampler was actually
  running, rather than going empty. Only trust those panels during/right after a
  `run-test-.sh` or `measure-startup.sh`.
