# =============================================================================
# Dockerfile — ESBMC-PLC+ Artifact (self-contained, linux/amd64)
#
# Reproduces all experiments from:
#   "ESBMC-PLC+: A Unified Framework for Formal Verification of IEC 61131-3
#    PLC Programs via ESBMC" (ARXIV)
#
# Build:
#   docker build -t esbmc-plcplus-artifact .
#
# Run all experiments:
#   docker run --rm esbmc-plcplus-artifact
#
# Save results to host:
#   docker run --rm -v "$(pwd)/results":/artifact/results esbmc-plcplus-artifact
# =============================================================================
FROM --platform=linux/amd64 ubuntu:22.04

LABEL maintainer="pierre.dantas@gmail.com"
LABEL description="ESBMC-PLC+ artifact — self-contained experiment runner"
LABEL version="1.0"

ENV DEBIAN_FRONTEND=noninteractive

ARG ESBMC_BINARY_URL=https://github.com/pierredantas/esbmc-plcplus-artifact/releases/download/v1.0/esbmc-linux-amd64

# ---------------------------------------------------------------------------
# Runtime dependencies
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y \
    libstdc++6 libgcc-s1 libgmp10 \
    libboost-date-time1.74.0 libboost-program-options1.74.0 \
    libboost-filesystem1.74.0 libboost-regex1.74.0 \
    libboost-iostreams1.74.0 libboost-atomic1.74.0 \
    libboost-container1.74.0 libboost-random1.74.0 \
    libxml2 unzip python3 python3-pip bash coreutils wget ca-certificates \
    && pip3 install --no-cache-dir pyyaml defusedxml \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Z3 4.13.3 shared library (matches the version linked into ESBMC binary)
# ---------------------------------------------------------------------------
RUN wget -q "https://github.com/Z3Prover/z3/releases/download/z3-4.13.3/z3-4.13.3-x64-glibc-2.35.zip" \
    -O /tmp/z3.zip \
    && unzip -q /tmp/z3.zip -d /tmp/z3 \
    && cp /tmp/z3/z3-4.13.3-x64-glibc-2.35/bin/libz3.so /usr/local/lib/ \
    && ldconfig \
    && rm -rf /tmp/z3.zip /tmp/z3

# ---------------------------------------------------------------------------
# ESBMC-PLC+ binary — downloaded from GitHub Release
# ---------------------------------------------------------------------------
RUN wget -q --show-progress "$ESBMC_BINARY_URL" -O /usr/local/bin/esbmc \
    && chmod +x /usr/local/bin/esbmc \
    && esbmc --version

# ---------------------------------------------------------------------------
# NuXmv 2.2.0 (linux64)
# ---------------------------------------------------------------------------
RUN wget -q "https://nuxmv.fbk.eu/downloads/2.2.0/nuXmv-2.2.0-linux64.tar.xz" \
    -O /tmp/nuXmv.tar.xz \
    && tar -xf /tmp/nuXmv.tar.xz -C /tmp/ \
    && cp /tmp/nuXmv-2.2.0-linux64/usr/local/bin/nuXmv /usr/local/bin/nuXmv \
    && chmod +x /usr/local/bin/nuXmv \
    && rm -rf /tmp/nuXmv.tar.xz /tmp/nuXmv-2.2.0-linux64 \
    && nuXmv --version 2>&1 | head -3 || true

# ---------------------------------------------------------------------------
# Artifact files
# ---------------------------------------------------------------------------
WORKDIR /artifact

COPY benchmarks/        benchmarks/
COPY st_benchmarks/     st_benchmarks/
COPY experiments/       experiments/
COPY run_all.sh         .

RUN chmod +x run_all.sh experiments/nuxmv_comparison/run_experiments.sh

ENV ESBMC=/usr/local/bin/esbmc
ENV NUXMV=/usr/local/bin/nuXmv

CMD ["bash", "run_all.sh", \
     "--esbmc", "/usr/local/bin/esbmc", \
     "--nuxmv", "/usr/local/bin/nuXmv"]
