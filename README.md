# graalvm-vs-jvm-performance

Compara duas apps Spring Boot idênticas (CRUD simples sobre `books` em Postgres) —
uma a correr em JVM normal, outra compilada para binário nativo com GraalVM — sob
carga, medindo CPU e memória.

## Como correr

```bash
docker compose up -d                # infraestrutura: apps, postgres, prometheus, grafana, cadvisor
./scripts/measure-startup.sh        # tempo de arranque + memória idle (antes de qualquer carga)
./k6/run-test-.sh                   # 3 repetições de carga sustentada por variante
```

Resultados do `run-test-.sh` ficam em `k6/results/`:
- `<label>-run<N>.txt` / `.json` — output e resumo estruturado do k6, por repetição
- `mem-cpu-<label>.csv` — amostras de CPU/memória real do container a cada 2s (bytes exatos, via API do Docker), cobrindo todas as repetições

Grafana em `http://localhost:3000` (dashboard "JVM vs GraalVM Native - CPU & Memory").
Enquanto o `sample-container-stats.sh` está a correr (chamado automaticamente pelo
`run-test-.sh`), os painéis "Container CPU/Memory Usage" mostram estes dados ao vivo,
via Pushgateway (`http://localhost:9091`) — contorna o cAdvisor, que não funciona no
Docker Desktop para Mac (ver abaixo).

## Limitações a ter em conta ao ler os resultados

- **GC diferente, não só runtime diferente.** O Java 17 (JVM) usa G1 por defeito. O
  GraalVM Community Edition (usado aqui) só suporta Serial GC no native-image — G1 no
  native-image só existe no Oracle GraalVM. Ou seja, os resultados refletem "JVM+G1"
  vs "Native+Serial GC", não só "JVM vs Native" isolado do algoritmo de GC.
- **O painel "JVM Memory Used" no Grafana não é uma comparação perfeitamente
  simétrica.** `jvm_memory_used_bytes` soma 7 pools na JVM (heap + Metaspace + Code
  Cache + Compressed Class Space) mas só 3 no native (eden/old/survivor) — o Substrate
  VM não tem os mesmos conceitos de Metaspace/Code Cache. Os painéis "Container
  CPU/Memory Usage" (memória total do container, vista de fora) são o número mais
  correto para comparação direta.
- **cAdvisor não reporta métricas por container no Docker Desktop para Mac** — é uma
  limitação conhecida da virtualização usada no Mac, não um erro de configuração. Por
  isso os painéis "Container CPU/Memory Usage" são alimentados pelo Pushgateway (via
  `sample-container-stats.sh`), não pelo cAdvisor.
- **O Pushgateway mantém o último valor empurrado indefinidamente**, mesmo depois do
  `sample-container-stats.sh` parar — os painéis "Container CPU/Memory Usage" vão
  mostrar uma linha reta e desatualizada fora das janelas em que o sampler esteve a
  correr, em vez de ficarem vazios. Só olhes para esses painéis durante/logo a seguir
  a um `run-test-.sh` ou `measure-startup.sh`.
