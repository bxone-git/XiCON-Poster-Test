#!/bin/bash
set -e

echo "=========================================="
echo "Container startup - $(date)"
echo "=========================================="

# Network Volume Setup
NETVOLUME="${NETWORK_VOLUME_PATH:-/runpod-volume}"

echo "Checking Network Volume at $NETVOLUME..."
if [ ! -d "$NETVOLUME" ]; then
    echo "ERROR: Network Volume not found at $NETVOLUME"
    echo "This endpoint requires a Network Volume with models"
    exit 1
fi

# Create symlinks
echo "Creating symlinks..."
rm -rf /ComfyUI/models/diffusion_models
rm -rf /ComfyUI/models/text_encoders
rm -rf /ComfyUI/models/vae

ln -sf $NETVOLUME/models/diffusion_models /ComfyUI/models/diffusion_models
ln -sf $NETVOLUME/models/text_encoders /ComfyUI/models/text_encoders
ln -sf $NETVOLUME/models/vae /ComfyUI/models/vae

echo "Symlinks created!"

# Model verification
check_model() {
    local model_path="$1"
    local model_name="$2"

    if [ ! -f "$model_path" ]; then
        echo "ERROR: Required model not found: $model_name"
        echo "Path: $model_path"
        exit 1
    fi
    echo "  [OK] $model_name"
}

echo "Verifying models..."
check_model "$NETVOLUME/models/diffusion_models/flux-2-klein-base-9b-fp8.safetensors" "KLEIN 9B"
check_model "$NETVOLUME/models/text_encoders/qwen_3_8b_fp8mixed.safetensors" "Qwen 3.8B CLIP"
check_model "$NETVOLUME/models/vae/flux2-vae.safetensors" "Flux2 VAE"

# GPU Detection and SageAttention setup
GPU_NAME=$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || echo "Unknown")
echo "Detected GPU: $GPU_NAME"

SAGE_FLAG=""
if echo "$GPU_NAME" | grep -qi "5090\|5080\|blackwell"; then
    echo "SageAttention: ENABLED (Blackwell SM120 - SageAttention2++ kernels)"
    export SAGEATTENTION_ENABLED=1
    SAGE_FLAG="--use-sage-attention"
elif echo "$GPU_NAME" | grep -qi "4090\|4080\|L40\|6000.*Ada\|ada"; then
    echo "SageAttention: ENABLED (Ada SM89 kernels)"
    export SAGEATTENTION_ENABLED=1
    SAGE_FLAG="--use-sage-attention"
else
    echo "SageAttention: DISABLED (unknown GPU architecture)"
fi

# Start ComfyUI
echo "Starting ComfyUI ${SAGE_FLAG:+with SageAttention}..."
python /ComfyUI/main.py --listen $SAGE_FLAG &

# Wait for ComfyUI
echo "Waiting for ComfyUI..."
max_wait=180
wait_count=0
while [ $wait_count -lt $max_wait ]; do
    if curl -s http://127.0.0.1:8188/ > /dev/null 2>&1; then
        echo "ComfyUI is ready!"
        break
    fi
    sleep 2
    wait_count=$((wait_count + 2))
done

if [ $wait_count -ge $max_wait ]; then
    echo "Error: ComfyUI failed to start"
    exit 1
fi

echo "Starting handler..."
exec python handler.py
