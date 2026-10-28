FROM nvidia/cuda:13.0.0-cudnn-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive

# System dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    wget \
    curl \
    cmake \
    pkg-config \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    libboost-all-dev \
    libeigen3-dev \
    libglu1-mesa \
    libglib2.0-0 \
    libxrender1 \
    libxext6 \
    libsm6 \
    && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:0.13.6 /uv /uvx /bin/

# Workspace
WORKDIR /app
# Keeps Python from buffering stdout and stderr to avoid situations where
# the application crashes without emitting any logs due to buffering.
ENV PYTHONUNBUFFERED=1

# Copy from the cache instead of linking since it's a mounted volume
ENV UV_LINK_MODE=copy

# Ensure installed tools can be executed out of the box
ENV UV_TOOL_BIN_DIR=/usr/local/bin

# Put the virtual environment OUTSIDE the mounted source tree
ENV UV_PROJECT_ENVIRONMENT=/opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

# Install the project's dependencies using the lockfile and settings
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --locked --no-install-project

# --------------------------------------------------------------------------
# Install RBDL + Python bindings into /opt/venv
# --------------------------------------------------------------------------
ARG RBDL_COMMIT=7dfbd4b1e8cebece9fa23042ef36094bf44d75a8
RUN git clone https://github.com/rbdl/rbdl.git /tmp/rbdl && \
    cd /tmp/rbdl && \
    git checkout "${RBDL_COMMIT}" && \
    git submodule update --init --recursive && \
    cmake -S . -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DRBDL_BUILD_PYTHON_WRAPPER=ON \
        -DRBDL_BUILD_ADDON_URDFREADER=ON && \
    cmake --build build -j$(nproc) && \
    cmake --install build && \
    cp -r build/python /opt/rbdl-python && \
    echo "/usr/local/lib" > /etc/ld.so.conf.d/rbdl.conf && \
    ldconfig && \
    rm -rf /tmp/rbdl

ENV PYTHONPATH=/opt/rbdl-python
ENV LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}

# Verification step
RUN python -c "import rbdl; print(rbdl.__file__)"

# Copy source
COPY . /app
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked

CMD ["/bin/bash"]