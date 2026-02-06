#!/bin/bash
# NEVER use set -e: handler must start for worker to register as ready

echo "=========================================="
echo "Container startup - $(date)"
echo "=========================================="

# Network Volume Setup
NETVOLUME="${NETWORK_VOLUME_PATH:-/runpod-volume}"

echo "Checking Network Volume at $NETVOLUME..."
if [ ! -d "$NETVOLUME" ]; then
    echo "WARNING: Network Volume not found at $NETVOLUME"
    echo "Handler will start but jobs will fail without models"
fi

# Create symlinks (only if volume exists)
if [ -d "$NETVOLUME/models" ]; then
    echo "Creating symlinks..."
    rm -rf /ComfyUI/models/diffusion_models
    rm -rf /ComfyUI/models/text_encoders
    rm -rf /ComfyUI/models/vae

    ln -sf $NETVOLUME/models/diffusion_models /ComfyUI/models/diffusion_models
    ln -sf $NETVOLUME/models/text_encoders /ComfyUI/models/text_encoders
    ln -sf $NETVOLUME/models/vae /ComfyUI/models/vae
    echo "Symlinks created!"
else
    echo "WARNING: $NETVOLUME/models not found, skipping symlinks"
fi

# Model verification (warnings only, never exit)
check_model() {
    local model_path="$1"
    local model_name="$2"

    if [ ! -f "$model_path" ]; then
        echo "  [MISSING] $model_name ($model_path)"
    else
        echo "  [OK] $model_name"
    fi
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
    echo "WARNING: ComfyUI failed to start within timeout, starting handler anyway"
fi

# CRITICAL: Handler MUST start for worker to register as ready
echo "Starting handler..."
exec python handler.py
