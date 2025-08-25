#!/bin/bash

source /venv/main/bin/activate
COMFYUI_DIR=${WORKSPACE}/ComfyUI

# Packages are installed after nodes so we can fix them...

APT_PACKAGES=(
    "cloudflared"
)

PIP_PACKAGES=(
    "fastapi"
    "uvicorn[standard]"
    "aiohttp"
    "boto3"
    "requests"
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

### DO NOT EDIT BELAY HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

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
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

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
ComfyUI Companion Server with Cloudflare Tunnel & S3 Integration
- Creates free Cloudflare tunnel for port 8000: cloudflared tunnel --url http://localhost:8000
- Extracts tunnel URL from cloudflared output
- Stores tunnel URL in S3 as instance_id.json (no paths)
- Minimal, focused functionality with auto-shutdown
"""

import os
import json
import logging
import subprocess
import asyncio
import aiohttp
from fastapi import FastAPI, HTTPException, Depends, Request
from fastapi.security import HTTPBearer
from fastapi.responses import JSONResponse, Response
import time
import signal
import threading
import boto3
from botocore.exceptions import ClientError
import re

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("comfyui-companion")

# Initialize FastAPI app
app = FastAPI(
    title="ComfyUI Companion Server",
    description="Companion server with Cloudflare tunnel and S3 integration",
    version="1.0.0"
)

# Security
security = HTTPBearer()

# Configuration from environment variables
API_TOKEN_SECRET = os.getenv("API_TOKEN_SECRET", "default-companion-token")
COMFYUI_URL = os.getenv("COMFYUI_URL", "http://localhost:18188")
COMPANION_PORT = int(os.getenv("COMPANION_PORT", "8000"))

# AWS configuration
AWS_ACCESS_KEY_ID = os.getenv("AWS_ACCESS_KEY_ID", "")
AWS_SECRET_ACCESS_KEY = os.getenv("AWS_SECRET_ACCESS_KEY", "")
AWS_S3_BUCKET = os.getenv("AWS_S3_BUCKET", "")
AWS_REGION = os.getenv("AWS_REGION", "us-east-1")

# Auto-shutdown configuration
AUTO_SHUTDOWN_MINUTES = int(os.getenv("AUTO_SHUTDOWN_MINUTES", "60"))
SHUTDOWN_GRACE_PERIOD = int(os.getenv("SHUTDOWN_GRACE_PERIOD", "300"))

# Vast.ai container information
VAST_CONTAINERLABEL = os.getenv("VAST_CONTAINERLABEL", "unknown")
CONTAINER_ID = VAST_CONTAINERLABEL.replace("C.", "")  # Remove "C." prefix
S3_KEY = f"{CONTAINER_ID}.json"  # Store as instance_id.json (no paths)

# Cloudflare tunnel management
tunnel_process = None
tunnel_url = None

# Activity tracking
last_activity_time = time.time()
shutdown_timer = None
is_shutting_down = False

async def verify_token(credentials: HTTPBearer = Depends(security)):
    """Verify the authentication token"""
    if credentials.credentials != API_TOKEN_SECRET:
        raise HTTPException(
            status_code=401, 
            detail="Invalid authentication token"
        )
    return credentials.credentials

def get_aws_client(service_name='s3'):
    """Get AWS client with proper credentials"""
    try:
        if AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY:
            session = boto3.Session(
                aws_access_key_id=AWS_ACCESS_KEY_ID,
                aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
                region_name=AWS_REGION
            )
        else:
            session = boto3.Session(region_name=AWS_REGION)
        
        return session.client(service_name)
    except Exception as e:
        logger.error(f"Failed to create AWS {service_name} client: {str(e)}")
        return None

async def upload_to_s3(data: dict):
    """Upload data to AWS S3 as instance_id.json"""
    if not AWS_S3_BUCKET:
        logger.warning("AWS_S3_BUCKET not configured, skipping S3 upload")
        return False
    
    try:
        s3_client = get_aws_client('s3')
        if not s3_client:
            return False
        
        s3_client.put_object(
            Bucket=AWS_S3_BUCKET,
            Key=S3_KEY,
            Body=json.dumps(data, indent=2),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        logger.info(f"Uploaded to S3: s3://{AWS_S3_BUCKET}/{S3_KEY}")
        return True
    except Exception as e:
        logger.error(f"Failed to upload to S3: {str(e)}")
        return False

async def delete_from_s3():
    """Delete data from AWS S3"""
    if not AWS_S3_BUCKET:
        return False
    
    try:
        s3_client = get_aws_client('s3')
        if not s3_client:
            return False
        
        s3_client.delete_object(
            Bucket=AWS_S3_BUCKET,
            Key=S3_KEY
        )
        logger.info(f"Deleted from S3: s3://{AWS_S3_BUCKET}/{S3_KEY}")
        return True
    except Exception as e:
        logger.error(f"Failed to delete from S3: {str(e)}")
        return False

def create_cloudflare_tunnel():
    """Create a free Cloudflare tunnel: cloudflared tunnel --url http://localhost:8000"""
    global tunnel_process, tunnel_url
    
    try:
        logger.info("Creating Cloudflare tunnel: cloudflared tunnel --url http://localhost:8000")
        
        # Simple cloudflared command without --name or other arguments
        tunnel_process = subprocess.Popen([
            "cloudflared", "tunnel", 
            "--url", f"http://localhost:{COMPANION_PORT}"
        ], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        
        # Wait for tunnel to establish
        time.sleep(8)  # Give it more time to establish
        
        if tunnel_process.poll() is not None:
            stderr = tunnel_process.stderr.read() if tunnel_process.stderr else "Unknown error"
            raise Exception(f"Tunnel process failed: {stderr}")
        
        # Extract tunnel URL from output using multiple patterns
        stdout_output = tunnel_process.stdout.read() if tunnel_process.stdout else ""
        stderr_output = tunnel_process.stderr.read() if tunnel_process.stderr else ""
        all_output = stdout_output + stderr_output
        
        logger.debug(f"Cloudflared output: {all_output}")
        
        # Try multiple patterns to extract URL
        url_patterns = [
            r'https://[a-zA-Z0-9-]+\.trycloudflare\.com',
            r'\| (https://[a-zA-Z0-9-]+\.trycloudflare\.com)',
            r'Your tunnel is available at (https://[a-zA-Z0-9-]+\.trycloudflare\.com)'
        ]
        
        for pattern in url_patterns:
            match = re.search(pattern, all_output)
            if match:
                tunnel_url = match.group(1) if len(match.groups()) > 0 else match.group(0)
                logger.info(f"Cloudflare tunnel created: {tunnel_url}")
                
                # Upload tunnel info to S3
                asyncio.create_task(upload_tunnel_info())
                
                return tunnel_url
        
        raise Exception("Failed to extract tunnel URL from cloudflared output")
            
    except Exception as e:
        logger.error(f"Failed to create Cloudflare tunnel: {str(e)}")
        if tunnel_process:
            tunnel_process.terminate()
        tunnel_process = None
        raise

async def upload_tunnel_info():
    """Upload tunnel information to S3 as instance_id.json"""
    if not tunnel_url:
        return False
    
    data = {
        "tunnel_url": tunnel_url,
        "container_id": CONTAINER_ID,
        "vast_containerlabel": VAST_CONTAINERLABEL,
        "companion_port": COMPANION_PORT,
        "comfyui_url": COMFYUI_URL,
        "created_at": time.time(),
        "public_ip": os.getenv('PUBLIC_IPADDR', 'unknown'),
        "instance_type": os.getenv('INSTANCE_TYPE', 'unknown')
    }
    
    return await upload_to_s3(data)

def stop_cloudflare_tunnel():
    """Stop the Cloudflare tunnel process"""
    global tunnel_process, tunnel_url
    
    if tunnel_process:
        try:
            if tunnel_process.poll() is None:
                tunnel_process.terminate()
                tunnel_process.wait(timeout=5)
                logger.info("Cloudflare tunnel stopped")
        except:
            pass
        tunnel_process = None
    
    tunnel_url = None

def update_activity():
    """Update the last activity time and reset shutdown timer"""
    global last_activity_time, shutdown_timer
    
    last_activity_time = time.time()
    
    # Reset shutdown timer
    if shutdown_timer:
        shutdown_timer.cancel()
    
    if AUTO_SHUTDOWN_MINUTES > 0:
        shutdown_timer = threading.Timer(
            AUTO_SHUTDOWN_MINUTES * 60,
            initiate_shutdown
        )
        shutdown_timer.daemon = True
        shutdown_timer.start()

def initiate_shutdown():
    """Initiate a graceful shutdown"""
    global is_shutting_down
    
    logger.info(f"Initiating shutdown due to inactivity after {AUTO_SHUTDOWN_MINUTES} minutes")
    is_shutting_down = True
    
    # Schedule actual shutdown after grace period
    shutdown_timer = threading.Timer(SHUTDOWN_GRACE_PERIOD, force_shutdown)
    shutdown_timer.daemon = True
    shutdown_timer.start()

def force_shutdown():
    """Force shutdown the server"""
    logger.info("Force shutting down server")
    os.kill(os.getpid(), signal.SIGTERM)

@app.middleware("http")
async def activity_middleware(request: Request, call_next):
    """Middleware to track activity on all requests"""
    update_activity()
    response = await call_next(request)
    return response

@app.get("/")
async def root(token: str = Depends(verify_token)):
    """Root endpoint with server info"""
    return {
        "message": "ComfyUI Companion Server",
        "version": "1.0.0",
        "comfyui_url": COMFYUI_URL,
        "container_id": CONTAINER_ID,
        "tunnel_url": tunnel_url,
        "tunnel_status": "active" if tunnel_url else "inactive",
        "aws_configured": bool(AWS_S3_BUCKET),
        "auto_shutdown_minutes": AUTO_SHUTDOWN_MINUTES,
        "last_activity": time.time() - last_activity_time
    }

@app.get("/health")
async def health_check():
    """Health check for ComfyUI and companion server"""
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(f"{COMFYUI_URL}/system_stats", timeout=5) as response:
                comfyui_healthy = response.status == 200
                comfyui_status = "healthy" if comfyui_healthy else "unhealthy"
                
        return {
            "comfyui": comfyui_status,
            "companion": "healthy",
            "tunnel": "active" if tunnel_url else "inactive",
            "container_id": CONTAINER_ID
        }
    except Exception as e:
        return {
            "comfyui": "unreachable",
            "companion": "healthy",
            "error": str(e)
        }

@app.get("/tunnel/info")
async def get_tunnel_info(token: str = Depends(verify_token)):
    """Get tunnel information"""
    if not tunnel_url:
        raise HTTPException(status_code=404, detail="Tunnel not active")
    
    return {
        "url": tunnel_url,
        "container_id": CONTAINER_ID,
        "status": "active"
    }

@app.post("/tunnel/restart")
async def restart_tunnel(token: str = Depends(verify_token)):
    """Restart the Cloudflare tunnel"""
    global tunnel_url
    
    # Stop existing tunnel
    stop_cloudflare_tunnel()
    
    # Create new tunnel
    try:
        new_url = create_cloudflare_tunnel()
        return {
            "message": "Tunnel restarted",
            "url": new_url,
            "container_id": CONTAINER_ID
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to restart tunnel: {str(e)}")

@app.post("/shutdown/now")
async def shutdown_now(grace_period: int = 60, token: str = Depends(verify_token)):
    """Initiate immediate shutdown"""
    global is_shutting_down
    
    if is_shutting_down:
        return {"message": "Shutdown already in progress"}
    
    is_shutting_down = True
    
    # Schedule shutdown
    threading.Timer(grace_period, force_shutdown).start()
    
    return {"message": f"Shutdown initiated. Will terminate in {grace_period} seconds."}

@app.post("/activity/reset")
async def reset_activity(token: str = Depends(verify_token)):
    """Reset the activity timer"""
    update_activity()
    return {"message": "Activity timer reset"}

@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD", "PATCH"])
async def proxy_comfyui(path: str, request: Request, token: str = Depends(verify_token)):
    """Proxy all requests to ComfyUI"""
    if is_shutting_down:
        raise HTTPException(status_code=503, detail="Server is shutting down")
    
    # Build the target URL
    target_url = f"{COMFYUI_URL}/{path}"
    if request.query_params:
        target_url += "?" + str(request.query_params)
    
    # Forward the request to ComfyUI
    try:
        async with aiohttp.ClientSession() as session:
            # Prepare request data
            data = await request.body() if request.method in ["POST", "PUT", "PATCH"] else None
            headers = dict(request.headers)
            
            # Remove host header to avoid issues
            headers.pop("host", None)
            
            # Make the request to ComfyUI
            async with session.request(
                method=request.method,
                url=target_url,
                headers=headers,
                data=data,
                timeout=30
            ) as response:
                # Return the response from ComfyUI
                content = await response.read()
                return Response(
                    content=content,
                    status_code=response.status,
                    headers=dict(response.headers)
                )
    except Exception as e:
        logger.error(f"Error proxying to ComfyUI: {str(e)}")
        raise HTTPException(status_code=502, detail=f"ComfyUI unreachable: {str(e)}")

@app.get("/container/info")
async def get_container_info():
    """Get container information (no authentication required)"""
    return {
        "container_id": CONTAINER_ID,
        "vast_containerlabel": VAST_CONTAINERLABEL,
        "public_ip": os.getenv('PUBLIC_IPADDR', 'unknown'),
        "gpu_count": os.getenv('GPU_COUNT', 'unknown')
    }

# Initialize on startup
@app.on_event("startup")
async def startup_event():
    """Initialize on startup"""
    logger.info(f"Companion server started on port {COMPANION_PORT}")
    logger.info(f"Container ID: {CONTAINER_ID}")
    logger.info(f"AWS configured: {bool(AWS_S3_BUCKET)}")
    logger.info(f"Auto-shutdown: {AUTO_SHUTDOWN_MINUTES} minutes")
    
    # Initialize activity tracking
    update_activity()
    
    # Create Cloudflare tunnel for the companion server
    try:
        create_cloudflare_tunnel()
    except Exception as e:
        logger.error(f"Failed to create Cloudflare tunnel on startup: {str(e)}")

# Cleanup on shutdown
@app.on_event("shutdown")
async def shutdown_event():
    """Clean up on shutdown"""
    logger.info("Shutting down companion server")
    
    # Stop Cloudflare tunnel
    stop_cloudflare_tunnel()
    
    # Clean up S3
    await delete_from_s3()
    
    # Cancel shutdown timer if it exists
    if shutdown_timer:
        shutdown_timer.cancel()

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        app, 
        host="0.0.0.0", 
        port=COMPANION_PORT,
        log_level="info"
    )
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
