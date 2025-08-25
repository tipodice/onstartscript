#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...

APT_PACKAGES=(
    # AWS CLI will be installed manually
)

PIP_PACKAGES=(
    # No Python packages needed for AWS CLI
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
        "${COMFYUI_DIR}/models/control极速net" \
        "${CONTROLNET_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/vae" \
        "${VAE_MODELS[@]}"
    provisioning_get_files \
        "${COMFYUI_DIR}/models/esrgan" \
        "${ESRGAN_MODELS[@]}"
    provisioning_setup_tunnel_upload
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
                   pip install --no-cache极速-dir -r "$requirements"
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
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #极速\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type": "application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="极速https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type": "application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $极速2 file path
function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/极速|$|\?) ]]; then
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

function provisioning_setup_tunnel_upload() {
    printf "Setting up AWS CLI and tunnel upload to S3...\n"
    
    # Install AWS CLI using the official method
    printf "Installing AWS CLI...\n"
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf awscliv2.zip aws/
    
    # Create a script to extract tunnel URL and upload to S3 using AWS CLI
    cat > /workspace/upload_tunnel.sh << 'EOF'
#!/bin/bash

# Wait for tunnel to be established
sleep 30

# Get container information
CONTAINER_ID=$(echo "$VAST_CONTAINERLABEL" | sed 's/C\.//')
S3_BUCKET="$AWS_S3_BUCKET"
S3_KEY="${CONTAINER_ID}.json"

# Configure AWS CLI
aws configure set aws_access_key_id "$AWS_ACCESS_KEY_ID"
aws configure set aws_secret_access_key "$AWS_SECRET_ACCESS_KEY"
aws configure set region "${AWS_REGION:-us-east-1}"

# Try to get tunnel URL from various sources
TUNNEL_URL=""

# Method 1: Try to get from portal API
if [ -z "$TUNNEL_URL" ]; then
    echo "Attempting to get tunnel URL from portal API..."
    if command -v curl &> /dev/null; then
        API_RESPONSE=$(curl -s http://localhost:11112/get-all-quick-tunnels || true)
        if [ -n "$API_RESPONSE" ]; then
            TUNNEL_URL=$(echo "$API_RESPONSE" | grep -o '"url":"[^"]*"' | grep -o 'http[^"]*' | head -1 || true)
        fi
    fi
fi

# Method 2: Try to find in logs
if [ -z "$TUNNEL_URL" ]; then
    echo "Searching for tunnel URL in logs..."
    LOG_FILES=("/var/log/onstart.log" "/var/log/portal/tunnel_manager.log")
    for LOG_FILE in "${LOG_FILES[@]}"; do
        if [ -f "$LOG_FILE" ]; then
            TUNNEL_URL=$(grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' "$LOG_FILE" | head -1 || true)
            if [ -n "$TUNNEL_URL" ]; then
                break
            fi
        fi
    done
fi

# If we found a tunnel URL, upload to S3
if [ -n "$TUNNEL_URL" ] && [ -n "$S3_BUCKET" ]; then
    echo "Found tunnel URL: $TUNNEL_URL"
    
    # Create JSON data
    JSON_DATA=$(cat <<END
{
    "tunnel_url": "$TUNNEL_URL",
    "container_id": "$CONTAINER_ID",
    "vast_containerlabel": "$VAST_CONTAINERLABEL",
    "public_ip": "${PUBLIC_IPADDR:-unknown}",
    "instance_type": "${INSTANCE_TYPE:-unknown}",
    "created_at": $(date +%s),
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
END
    )
    
    # Create temp file
    TEMP_FILE=$(mktemp)
    echo "$JSON_DATA" > "$TEMP_FILE"
    
    # Upload to S3 using AWS CLI
    echo "Uploading tunnel info to S3..."
    if aws s3 cp "$TEMP_FILE" "s3://$S3_BUCKET/$S3_KEY"; then
        echo "Successfully uploaded tunnel information to S3"
    else
        echo "Failed to upload to S3"
    fi
    
    # Clean up
    rm -f "$TEMP_FILE"
else
    echo "Could not find tunnel URL or S3 bucket not configured"
fi
EOF

    # Make the script executable
    chmod +x /workspace/upload_tunnel.sh
    
    # Create a systemd service to run the upload script
    cat > /etc/systemd/system/upload-tunnel.service << EOF
[Unit]
Description=Upload Vast.ai tunnel info to S3
After=network.target

[Service]
Type=oneshot
Environment=VAST_CONTAINERLABEL=$VAST_CONTAINERLABEL
Environment=AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
Environment=AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
Environment=AWS_S3_BUCKET=$AWS_S3_BUCKET
Environment=AWS_REGION=$AWS_REGION
Environment=PUBLIC_IPADDR=$PUBLIC_IPADDR
Environment=INSTANCE_TYPE=$INSTANCE_TYPE
ExecStart=/bin/bash /workspace/upload_tunnel.sh
User=root

[Install]
WantedBy=multi-user.target
EOF

    # Enable and start the service
    systemctl daemon-reload
    systemctl enable upload-tunnel.service
    systemctl start upload-tunnel.service
    
    printf "Tunnel upload service setup complete. Tunnel information will be uploaded to S3.\n"
}

# Allow user to disable provisioning if they started with a script they didn't want
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi
