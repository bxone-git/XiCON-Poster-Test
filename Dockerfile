# Poster Maker I2I - Ada GPU Optimized
# CUDA 12.4 + PyTorch cu124 + SageAttention
# Supports: RTX 4090, RTX 6000 Ada, L40, L40S

FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV TORCH_CUDA_ARCH_LIST="8.9"

# System dependencies
RUN apt-get update && apt-get install -y \
    python3.10 python3-pip python3.10-venv \
    git curl wget \
    libgl1-mesa-glx libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.10 /usr/bin/python

# PyTorch with CUDA 12.4
RUN pip install --upgrade pip && \
    pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu124

# SageAttention will be installed at runtime (requires GPU for CUDA kernel compilation)

# Python packages
RUN pip install -U "huggingface_hub[hf_transfer]" runpod websocket-client

WORKDIR /

# ComfyUI
RUN git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git && \
    cd /ComfyUI && pip install -r requirements.txt

# Custom nodes (minimal for Flux 2 Klein)
RUN cd /ComfyUI/custom_nodes && \
    git clone --depth 1 https://github.com/Comfy-Org/ComfyUI-Manager.git && \
    cd ComfyUI-Manager && pip install -r requirements.txt

RUN cd /ComfyUI/custom_nodes && \
    git clone --depth 1 https://github.com/kijai/ComfyUI-KJNodes && \
    cd ComfyUI-KJNodes && pip install -r requirements.txt

# Model directories (symlinked at runtime)
RUN mkdir -p /ComfyUI/models/diffusion_models \
    /ComfyUI/models/text_encoders \
    /ComfyUI/models/vae

# NO MODEL DOWNLOADS - Network Volume 사용

COPY . .
RUN mkdir -p /ComfyUI/user/default/ComfyUI-Manager
COPY config.ini /ComfyUI/user/default/ComfyUI-Manager/config.ini
RUN chmod +x /entrypoint.sh
RUN chmod +x /setup_netvolume.sh 2>/dev/null || true

CMD ["/entrypoint.sh"]
