# AI/LLM 领域 CDN 与模型资源域名配置
#
# 以下场景查询参数可安全移除 (参数仅用于签名/跟踪, 内容按路径寻址):
#   - Hugging Face LFS CDN: AWS 签名参数, 文件按 oid 内容寻址
#   - Hugging Face Xet 存储: 签名参数, chunk 按哈希寻址
#   - Ollama blobs: sha256 内容寻址
#   - PyTorch/NVIDIA/OpenAI/Meta 公开文件: 版本/哈希在路径中
#
# 不做 store_id 重写的域名 (参数影响返回内容):
#   - huggingface.co / hf-mirror.com (API 查询)
#   - modelscope.cn (?Revision=&FilePath= 决定返回文件)
#   - models.dev/api.json 以外的动态内容

# 模型权重类文件扩展名 (用于 GCS 等通用存储桶, 避免误伤 alt=media 等参数语义)
_LLM_MODEL_FILE_EXTS = (r'safetensors|bin|gguf|ckpt|pt|pth|h5|pb|'
                        r'onnx|tflite|npz|msgpack')

LLM_SAFE_STRIP_DOMAINS = [
    # Hugging Face LFS CDN
    # URL: cdn-lfs-us-1.huggingface.co/<oid>?X-Amz-Algorithm=...&X-Amz-Signature=...
    r'^https?://cdn-lfs[^/]*\.huggingface\.co/',
    r'^https?://cdn-lfs[^/]*\.hf\.co/',
    r'^https?://cdn-lfs[^/]*\.hf-mirror\.com/',

    # Hugging Face Xet 存储
    # URL: transfer.xethub.hf.co/...?X-Xet-Signed-Range=... 等签名参数
    r'^https?://transfer\.xethub\.hf\.co/',
    r'^https?://cas-bridge\.xethub\.hf\.co/',

    # Ollama registry blobs (sha256 内容寻址)
    # URL: registry.ollama.ai/v2/library/<model>/blobs/sha256:<hash>
    r'^https?://registry\.ollama\.ai/v2/[^/]+/[^/]+/blobs/sha256:',

    # PyTorch 官方 wheel
    # URL: download.pytorch.org/whl/cu121/torch-2.x.x%2Bcu121-cp310-...whl
    r'^https?://download\.pytorch\.org/',

    # NVIDIA Python wheel / CUDA 安装包
    r'^https?://pypi\.nvidia\.com/',
    r'^https?://developer\.download\.nvidia\.com/',

    # OpenAI 公开资源 (tiktoken 编码表 / whisper / CLIP)
    # URL: openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken
    # URL: openaipublic.azureedge.net/main/whisper/models/<hash>/large-v3.pt
    r'^https?://openaipublic\.blob\.core\.windows\.net/',
    r'^https?://openaipublic\.azureedge\.net/',

    # Meta AI 公开模型文件 (SAM/DINO 等)
    # URL: dl.fbaipublicfiles.com/segment_anything/sam_vit_h_4b8939.pth
    r'^https?://dl\.fbaipublicfiles\.com/',

    # Replicate 权重 CDN (签名 URL, 内容不可变)
    # URL: weights.replicate.delivery/default/xxx.tar?... 等签名参数
    r'^https?://replicate\.delivery/',
    r'^https?://weights\.replicate\.delivery/',
    r'^https?://pbxt\.replicate\.delivery/',

    # Google Cloud Storage 公开桶模型文件 (仅模型权重类扩展名)
    # 注意: GCS 的 ?alt=media 等参数影响返回内容, 故只对模型文件扩展名去 query
    rf'^https?://storage\.googleapis\.com/.*\.(?:{_LLM_MODEL_FILE_EXTS})(?:\?.*)?$',
    rf'^https?://commondatastorage\.googleapis\.com/.*\.(?:{_LLM_MODEL_FILE_EXTS})(?:\?.*)?$',

    # models.dev 哈希静态资源
    # URL: models.dev/_astro/<name>.<hash>.js
    r'^https?://models\.dev/_astro/',
]

# models.dev 的 /api.json 以及 huggingface.co/modelscope.cn 的元数据不做重写
# (参数影响内容或需要保持最新)
# civitai.com 的图片变换参数 (width/original 等) 影响内容, 也不做重写
