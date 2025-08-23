#!/bin/bash

apt update &&

apt upgrade -y &&

cd /workspace/ComfyUI &&

git pull origin master && 

pip install comfy

pip install -r requirements.txt &&

cd /workspace/ComfyUI/custom_nodes &&

git clone https://github.com/ClownsharkBatwing/RES4LYF.git &&

git clone https://github.com/M1kep/ComfyLiterals.git &&

git clone https://github.com/city96/ComfyUI-GGUF.git &&

git clone https://github.com/WASasquatch/was-node-suite-comfyui.git &&

git clone https://github.com/rgthree/rgthree-comfy.git &&

git clone https://github.com/cubiq/ComfyUI_essentials.git &&

git clone https://github.com/kijai/ComfyUI-KJNodes.git &&

wget -P /workspace/ComfyUI/models/loras/ https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors &&

wget -P /workspace/ComfyUI/models/loras/ https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors && 

wget -P /workspace/ComfyUI/models/diffusion_models/ https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors &&

wget -P /workspace/ComfyUI/models/diffusion_models/ https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/diffusion_models/wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors &&

wget -P /workspace/ComfyUI/models/unet https://huggingface.co/QuantStack/Wan2.2-T2V-A14B-GGUF/resolve/main/LowNoise/Wan2.2-T2V-A14B-LowNoise-Q6_K.gguf &&

wget -P /workspace/ComfyUI/models/unet https://huggingface.co/QuantStack/Wan2.2-T2V-A14B-GGUF/resolve/main/HighNoise/Wan2.2-T2V-A14B-HighNoise-Q6_K.gguf &&

wget -P /workspace/ComfyUI/models/loras https://huggingface.co/Kijai/WanVideo_comfy/resolve/main/Wan21_T2V_14B_lightx2v_cfg_step_distill_lora_rank32.safetensors &&

wget -P /workspace/ComfyUI/models/text_encoders https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/text_encoders/umt5_xxl_fp8_e4m3fn_scaled.safetensors && 

wget -P /workspace/ComfyUI/models/vae https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors &&

wget -P /workspace/ComfyUI/models/loras "https://civitai.com/api/download/models/2075971?type=Model&format=SafeTensor" --content-disposition &&

wget -P /workspace/ComfyUI/models/loras "https://civitai.com/api/download/models/2075810?type=Model&format=SafeTensor" --content-disposition
