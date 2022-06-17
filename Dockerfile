# Copyright (c) 2022 MobileCoin Inc.

FROM ubuntu:focal-20220426 as rust-sgx-base

# Utilities:
# build-essential, cmake, curl, git, jq
#
# Build Requirements:
# libclang-dev, libprotobuf-dev, libpq-dev, libssl1.1,
# libssl-dev, llvm, llvm-dev, pkg-config, protobuf-compiler
#
# Needed for GHA cache actions:
# zstd
RUN  ln -fs /usr/share/zoneinfo/Etc/UTC /etc/localtime \
  && apt-get update \
  && apt-get upgrade -y \
  && apt-get install -y \
     build-essential \
     clang \
     cmake \
     curl \
     git \
     jq \
     libclang-dev \
     libprotobuf-dev \
     libpq-dev \
     libssl1.1 \
     libssl-dev \
     llvm \
     llvm-dev \
     pkg-config \
     protobuf-compiler \
     wget \
     zstd \
  && apt-get clean \
  && rm -r /var/lib/apt/lists

SHELL ["/bin/bash", "-c"]
# Install SGX

ARG SGX_URL=https://download.01.org/intel-sgx/sgx-linux/2.17/distro/ubuntu20.04-server/sgx_linux_x64_sdk_2.17.100.3.bin
RUN  curl -o sgx.bin "${SGX_URL}" \
  && chmod +x ./sgx.bin \
  && ./sgx.bin --prefix=/opt/intel \
  && rm ./sgx.bin

ENV SGX_SDK=/opt/intel/sgxsdk
ENV PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/intel/sgxsdk/bin:/opt/intel/sgxsdk/bin/x64
ENV PKG_CONFIG_PATH=/opt/intel/sgxsdk/pkgconfig
ENV LD_LIBRARY_PATH=/opt/intel/sgxsdk/sdk_libs

# Github actions overwrites the runtime home directory, so we need to install in a global directory.
ENV RUSTUP_HOME=/opt/rustup
ENV CARGO_HOME=/opt/cargo
RUN  mkdir -p ${RUSTUP_HOME} \
  && mkdir -p ${CARGO_HOME}/bin

# Install rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
  sh -s -- -y --default-toolchain nightly-2022-04-29


# Set up the builder-install image with more test helpers for CI.
FROM rust-sgx-base AS builder-install
RUN apt-get update \
  && apt-get install -y \
    nginx \
    postgresql \
    postgresql-client \
    python3 \
    python3-pip \
  && apt-get clean \
  && rm -r /var/lib/apt/lists

# Setup postgresql for local testing
RUN sed -i \
  -e 's|host    all             all             127.0.0.1/32            md5|host    all             all             127.0.0.1/32            trust|'\
  -e 's|host    all             all             ::1/128                 md5|host    all             all             ::1/128                 trust|' \
  /etc/postgresql/*/main/pg_hba.conf
RUN service postgresql start && su postgres -c "createuser --superuser root"

# Install  Cargo test helpers from released binaries.
# TODO: Remove cargo2junit and other unused helpers when we migrate off of CircleCI.
RUN curl -LsSf https://get.nexte.st/latest/linux | tar zxf - -C ${CARGO_HOME:-~/.cargo}/bin && \
    curl -LsSf https://github.com/mozilla/sccache/releases/download/v0.3.0/sccache-v0.3.0-x86_64-unknown-linux-musl.tar.gz | tar xzf - -C ${CARGO_HOME:-~/.cargo}/bin && \
    curl -LsSf https://github.com/eqrion/cbindgen/releases/download/v0.24.2/cbindgen -o ${CARGO_HOME:-~/.cargo}/bin/cbindgen && \
    curl -LsSf https://github.com/ryankurte/cargo-binstall/releases/latest/download/cargo-binstall-x86_64-unknown-linux-musl.tgz | tar xzf - -C ${CARGO_HOME:-~/.cargo}/bin && \
    for crate in cargo-cache cargo-tree cargo2junit; do cargo binstall --no-confirm $crate; done

WORKDIR /
# Party like it's June 8th, 1989.
SHELL ["/bin/bash", "-c"]
