# ESBMC-PLC+ Artifact

Reproducibility artifact for:

> **ESBMC-PLC+: A Unified Framework for Formal Verification of IEC 61131-3 PLC Programs via ESBMC**

## Quickstart (any OS with Docker)

```bash
docker pull ghcr.io/pierredantas/esbmc-plcplus-artifact:artifact
docker run --rm ghcr.io/pierredantas/esbmc-plcplus-artifact:artifact
```

Save results to your host:

```bash
docker run --rm \
  -v "$(pwd)/results":/artifact/results \
  ghcr.io/pierredantas/esbmc-plcplus-artifact:artifact
```

## What it runs

| RQ | Benchmark | Expected |
|----|-----------|----------|
| RQ1 | D1 — motor_sequencing (ST via MATIEC) | VIOLATION at k=2 |
| RQ2 | C1 — beremiz_traffic_light (graphical LD + function blocks) | SAFE |
| RQ4 | A1–A13, B1–B3 — inherited LD benchmarks (zero regressions) | as reported |
| RQ5 | ESBMC-PLC+ vs nuXmv BDD/IC3 (8 runs, timeout 120s) | see Table |

## Repository layout

```
benchmarks/          # LD benchmark programs and YAML property files
st_benchmarks/       # ST benchmark programs
experiments/
  nuxmv_comparison/  # LD→SMV translator, nuXmv runner, table generator
run_all.sh           # Single entry point — reproduces all results
Dockerfile           # Self-contained image (downloads ESBMC binary from Release)
```

## Building the image locally

```bash
docker build -t esbmc-plcplus-artifact .
docker run --rm esbmc-plcplus-artifact
```

## ESBMC-PLC+ source

The ESBMC-PLC+ implementation is available as PR [#5400](https://github.com/esbmc/esbmc/pull/5400) in the ESBMC repository.

## License

Benchmark programs: MIT.
ESBMC: MIT (see [esbmc/esbmc](https://github.com/esbmc/esbmc)).
NuXmv: academic/non-commercial — see [nuxmv.fbk.eu](https://nuxmv.fbk.eu).
