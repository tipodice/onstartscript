#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...

APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

PIP_PACKAGES=(
    "fastapi"
    "uvicorn[standard]"
    "aiohttp"
    #"package-1"
    #"package-2"
)

NODES=(
    #"https://github.com/ltdrdata/ComfyUI-Manager"
    #"https://github.com/cubiq/ComfyUI_essentials"
)

WORKFLOWS=(

)

CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/798204?type=Model&format=SafeTensor&size=full&fp=fp16"
)

UNET_MODELS=(
)

LORA_MODELS=(
)

VAE_MODELS=(
)

ESRGAN_MODELS=(
)

CONTROLNET_MODELS=(
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    provisioning_get_nodes
    provisioning_get_pip_packages
    provisioning_get_files \
        "${COMFYUI_DIR}/models/checkpoints" \
        "${CHECKPOINT_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/unet" \
        "${UNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/lora" \
        "${LORA_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/controlnet" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_setup_companion_server
    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_nodes() {
    for repo in "${NODES[@]}"; do
        dir="${repo##*/}"
        path="${COMFYUI_DIR}custom_nodes/${dir}"
        requirements="${path}/requirements.txt"
        if [[ -d $path ]]; then
            if [[ ${AUTO_UPDATE,,} != "false" ]]; then
                printf "Updating node: %s...\n" "${repo}"
                ( cd "$path" && git pull )
                if [[ -e $requirements ]]; then
                   pip install --no-cache-dir -r "$requirements"
                fi
            fi
        else
            printf "Downloading node: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
            if [[ -e $requirements ]]; then
                pip install --no-cache-dir -r "${requirements}"
            fi
        fi
    done
}

function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 file path
function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif 
        [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]];then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

function provisioning_setup_companion_server() {
    printf "Setting up ComfyUI Companion Server...\n"
    
    # Create the companion server script
    cat > /workspace/comfyui_companion.py << 'EOF'
#!/usr/bin/env python3
"""
Simple ComfyUI Companion Server for Testing
"""

import os
import json
from fastapi import FastAPI
from fastapi.responses import JSONResponse
import aiohttp
import asyncio

app = FastAPI(title="ComfyUI Companion")

# Configuration
WORKSPACE = os.getenv("WORKSPACE", "/workspace")
COMFYUI_DIR = os.path.join(WORKSPACE, "ComfyUI")
COMFYUI_URL = "http://localhost:8188"
COMPANION_PORT = 8000

@app.get("/")
async def root():
    """Simple root endpoint"""
    return {"message": "ComfyUI Companion Server", "status": "running"}

@app.get("/health")
async def health():
    """Check if ComfyUI is running"""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{COMFYUI_URL}/system_stats", timeout=5) as response:
                comfy_healthy = response.status == 200
                return {"comfyui": comfy_healthy, "status": "healthy" if comfy_healthy else "unhealthy"}
    except Exception:
        return {"comfyui": False, "status": "unhealthy"}

@app.get("/models")
async def list_models():
    """List available models"""
    models = {}
    model_types = ["checkpoints", "loras", "controlnet"]
    
    for model_type in model_types:
        model_dir = os.path.join(COMFYUI_DIR, "models", model_type)
        if os.path.exists(model_dir):
            models[model_type] = []
            for file in os.listdir(model_dir):
                if file.endswith(('.safetensors', '.ckpt', '.pt')):
                    models[model_type].append(file)
    
    return models

if __name__ == "__main__":
    import uvicorn
    print(f"Starting ComfyUI Companion Server on port {COMPANION_PORT}")
    uvicorn.run(app, host="0.0.0.0", port=COMPANION_PORT)
EOF

    # Make the script executable
    chmod +x /workspace/comfyui_companion.py
    
    # Create a supervisor configuration to start the server automatically
    cat > /etc/supervisor/conf.d/comfyui-companion.conf << 'EOF'
[program:comfyui-companion]
command=/venv/main/bin/python /workspace/comfyui_companion.py
directory=/workspace
autostart=true
autorestart=true
stderr_logfile=/var/log/portal/comfyui-companion.err.log
stdout_logfile=/var/log/portal/comfyui-companion.out.log
environment=PYTHONUNBUFFERED=1
EOF

    # Update supervisor to include the new configuration
    supervisorctl update
    
    # Update PORTAL_CONFIG to include the companion server
    # This ensures the companion server is accessible through the Instance Portal
    if [ -f /etc/portal.yaml ]; then
        # Check if companion server is already in the config
        if ! grep -q "Companion Server" /etc/portal.yaml; then
            # Add companion server to the config
            sed -i '/^applications:/a\  - host: localhost\n    external_port: 8000\n    local_port: 8000\n    path: /\n    name: Companion Server' /etc/portal.yaml
        fi
    else
        # Create a new portal.yaml if it doesn't exist
        cat > /etc/portal.yaml << 'EOF'
applications:
  - host: localhost
    external_port: 8000
    local_port: 8000
    path: /
    name: Companion Server
EOF
    fi
    
    # Restart caddy to apply changes
    supervisorctl restart caddy
    
    printf "Companion server setup complete. It will start automatically.\n"
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
