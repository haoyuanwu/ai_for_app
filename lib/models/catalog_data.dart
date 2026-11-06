// 国内厂商候选；文件清单核对于 2026-11-04，固定 revision / 大小 / SHA-256。
const catalogData = r'''[
  {
    "id": "qwen35-08b-q4",
    "name": "Qwen3.5 0.8B",
    "repo": "unsloth/Qwen3.5-0.8B-GGUF",
    "revision": "6ab461498e2023f6e3c1baea90a8f0fe38ab64d0",
    "format": "gguf",
    "capabilities": [
      "chat",
      "vision"
    ],
    "description": "Qwen3.5 文字对话与图片理解，自动配齐同仓库 F16 投影。合计约 0.74 GB，运行时还需预留上下文与图像编码内存；可按需分配给文字和图片功能。当前不支持音频或直接视频输入，工具调用与手机效果需实测。",
    "variant": "Q4_K_M + mmproj F16",
    "files": [
      {
        "path": "Qwen3.5-0.8B-Q4_K_M.gguf",
        "bytes": 532517120,
        "sha256": "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517"
      },
      {
        "path": "mmproj-F16.gguf",
        "bytes": 204987232,
        "sha256": "56e4c6cfe73b0c82e3e82bc518d7591997e61d81f723fc41a586f4fa69ea2453"
      }
    ],
    "vendor": "阿里 · Qwen",
    "upstream": "Qwen/Qwen3.5-0.8B",
    "highMemory": false
  },
  {
    "id": "qwen35-2b-q4",
    "name": "Qwen3.5 2B",
    "repo": "unsloth/Qwen3.5-2B-GGUF",
    "revision": "f6d5376be1edb4d416d56da11e5397a961aca8ae",
    "format": "gguf",
    "capabilities": [
      "chat",
      "vision"
    ],
    "description": "Qwen3.5 文字对话与图片理解，自动配齐同仓库 F16 投影。合计约 1.95 GB，运行时还需预留上下文与图像编码内存；可按需分配给文字和图片功能。当前不支持音频或直接视频输入，工具调用与手机效果需实测。",
    "variant": "Q4_K_M + mmproj F16",
    "files": [
      {
        "path": "Qwen3.5-2B-Q4_K_M.gguf",
        "bytes": 1280835840,
        "sha256": "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223"
      },
      {
        "path": "mmproj-F16.gguf",
        "bytes": 668227264,
        "sha256": "7035e9cb8d7c6a9681d07eef9a364783e86ea4cd73faab2eabb4f43a101830c7"
      }
    ],
    "vendor": "阿里 · Qwen",
    "upstream": "Qwen/Qwen3.5-2B",
    "highMemory": false
  },
  {
    "id": "qwen35-4b-q4",
    "name": "Qwen3.5 4B",
    "repo": "unsloth/Qwen3.5-4B-GGUF",
    "revision": "e87f176479d0855a907a41277aca2f8ee7a09523",
    "format": "gguf",
    "capabilities": [
      "chat",
      "vision"
    ],
    "description": "Qwen3.5 文字对话与图片理解，自动配齐同仓库 F16 投影。合计约 3.41 GB，运行时还需预留上下文与图像编码内存；仅建议高内存设备试用。当前不支持音频或直接视频输入，工具调用与手机效果需实测。",
    "variant": "Q4_K_M + mmproj F16",
    "files": [
      {
        "path": "Qwen3.5-4B-Q4_K_M.gguf",
        "bytes": 2740937888,
        "sha256": "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4"
      },
      {
        "path": "mmproj-F16.gguf",
        "bytes": 672423616,
        "sha256": "cd88edcf8d031894960bb0c9c5b9b7e1fea6ebee02b9f7ce925a00d12891f864"
      }
    ],
    "vendor": "阿里 · Qwen",
    "upstream": "Qwen/Qwen3.5-4B",
    "highMemory": true
  },
  {
    "id": "qwen35-9b-q4",
    "name": "Qwen3.5 9B",
    "repo": "unsloth/Qwen3.5-9B-GGUF",
    "revision": "3885219b6810b007914f3a7950a8d1b469d598a5",
    "format": "gguf",
    "capabilities": [
      "chat",
      "vision"
    ],
    "description": "Qwen3.5 文字对话与图片理解，自动配齐同仓库 F16 投影。合计约 6.60 GB，运行时还需预留上下文与图像编码内存；仅建议高内存设备试用。当前不支持音频或直接视频输入，工具调用与手机效果需实测。",
    "variant": "Q4_K_M + mmproj F16",
    "files": [
      {
        "path": "Qwen3.5-9B-Q4_K_M.gguf",
        "bytes": 5680522464,
        "sha256": "03b74727a860a56338e042c4420bb3f04b2fec5734175f4cb9fa853daf52b7e8"
      },
      {
        "path": "mmproj-F16.gguf",
        "bytes": 918166080,
        "sha256": "f70dc3509053962b0d0d3ee8a7eacebf5d60aa560cad78254ae8698516ae029f"
      }
    ],
    "vendor": "阿里 · Qwen",
    "upstream": "Qwen/Qwen3.5-9B",
    "highMemory": true
  },
  {
    "id": "minicpm5-2b-q4",
    "name": "MiniCPM5 2B",
    "repo": "openbmb/MiniCPM5-2B-GGUF",
    "revision": "2079a22f3beaa4e306449978533478fe0522f4b3",
    "format": "gguf",
    "capabilities": [
      "chat"
    ],
    "description": "面壁智能轻量中文对话模型。使用官方 GGUF；自动整理与工具调用效果需在当前引擎和设备上实测。",
    "variant": "Q4_K_M",
    "files": [
      {
        "path": "MiniCPM5-2B-Q4_K_M.gguf",
        "bytes": 1561318368,
        "sha256": "ec2d5801640099e97d8d7e8003ad4d81f336e757811f03a26173dddf386602fd"
      }
    ],
    "vendor": "面壁智能 · MiniCPM",
    "upstream": "openbmb/MiniCPM5-2B",
    "highMemory": false
  },
  {
    "id": "deepseek-r1-15b-q4",
    "name": "DeepSeek R1 Distill 1.5B",
    "vendor": "DeepSeek",
    "upstream": "deepseek-ai/DeepSeek-R1-Distill-Qwen-1.5B",
    "highMemory": false,
    "repo": "unsloth/DeepSeek-R1-Distill-Qwen-1.5B-GGUF",
    "revision": "3cb4d15544a2a5e07439592b9a0965b6445fbd34",
    "format": "gguf",
    "capabilities": [
      "chat"
    ],
    "description": "推理型蒸馏模型。小参数不等于完整 DeepSeek 能力；快速记录、JSON 和工具调用需要实测。",
    "variant": "Q4_K_M",
    "files": [
      {
        "path": "DeepSeek-R1-Distill-Qwen-1.5B-Q4_K_M.gguf",
        "bytes": 1117321312,
        "sha256": "f3bdf9cf31dee4b57ae4e455a1cb0d01b5c2c1b50d72d3112141c195506c2840"
      }
    ]
  },
  {
    "id": "deepseek-r1-7b-q4",
    "name": "DeepSeek R1 Distill 7B",
    "repo": "unsloth/DeepSeek-R1-Distill-Qwen-7B-GGUF",
    "revision": "097680e4eed7a83b3df6b0bb5e5134099cadf1b0",
    "format": "gguf",
    "capabilities": [
      "chat"
    ],
    "description": "DeepSeek 推理蒸馏模型的社区量化版。需要更多运行内存；思考文本较长，记录提取和工具调用需实测。",
    "variant": "Q4_K_M",
    "files": [
      {
        "path": "DeepSeek-R1-Distill-Qwen-7B-Q4_K_M.gguf",
        "bytes": 4683073248,
        "sha256": "78272d8d32084548bd450394a560eb2d70de8232ab96a725769b1f9171235c1c"
      }
    ],
    "vendor": "DeepSeek",
    "upstream": "deepseek-ai/DeepSeek-R1-Distill-Qwen-7B",
    "highMemory": true
  },
  {
    "id": "mimo-7b-rl-q4",
    "name": "小米 MiMo 7B RL",
    "vendor": "小米 · MiMo",
    "upstream": "XiaomiMiMo/MiMo-7B-RL",
    "highMemory": true,
    "repo": "jedisct1/MiMo-7B-RL-GGUF",
    "revision": "d6735a3346b372364aa3f2a591635a8f70c1c9d1",
    "format": "gguf",
    "capabilities": [
      "chat"
    ],
    "description": "小米推理模型的社区量化版。约 4.68 GB 权重，需要更多运行内存；仅供高内存设备试用，不推荐普通手机。未启用 MTP。",
    "variant": "Q4_K_M",
    "files": [
      {
        "path": "MiMo-7B-RL-Q4_K_M.gguf",
        "bytes": 4684339808,
        "sha256": "9142f02e34f64da37ae411dbde4059f5e5aac8aba32f261608d1c6f79f0c2eae"
      }
    ]
  },
  {
    "id": "qwen3vl-4b-q4",
    "name": "Qwen3 VL 4B Instruct",
    "repo": "Qwen/Qwen3-VL-4B-Instruct-GGUF",
    "revision": "1cd86afb9a95c410a6038ab3b40d8b578c892266",
    "format": "gguf",
    "capabilities": [
      "chat",
      "vision"
    ],
    "description": "中文图片理解、OCR 和文字对话候选，自动下载配套投影。合计约 2.95 GB，需额外图像编码内存；当前仅支持图片，不直接接收视频或音频。",
    "variant": "Q4_K_M + mmproj Q8_0",
    "files": [
      {
        "path": "Qwen3VL-4B-Instruct-Q4_K_M.gguf",
        "bytes": 2497281664,
        "sha256": "66358cb18bb6b3b1b6675aa412c7a88ef01d228f481184d13668e5201c730a0a"
      },
      {
        "path": "mmproj-Qwen3VL-4B-Instruct-Q8_0.gguf",
        "bytes": 453974304,
        "sha256": "30ba2c7dd3127a4561b6cba9d13d0f711c91bdb38742e2f56d73c8cb596bd06d"
      }
    ],
    "vendor": "阿里 · Qwen",
    "upstream": "Qwen/Qwen3-VL-4B-Instruct",
    "highMemory": true
  },
  {
    "id": "minicpmv-47-1b-q4",
    "name": "MiniCPM-V 4.7 1B",
    "repo": "openbmb/MiniCPM-V-4.7-1B-gguf",
    "revision": "345adbfa02c4a4671e61b7c75502dc9bf24fa93d",
    "format": "gguf",
    "capabilities": [
      "chat",
      "vision"
    ],
    "description": "轻量图片理解与 OCR 候选。自动配齐标准投影，合计约 1.78 GB；当前引擎兼容性需实测，不包含语音或直接视频输入。",
    "variant": "Q4_K_M + mmproj F16",
    "files": [
      {
        "path": "MiniCPM-V-4_7-1B-Q4_K_M.gguf",
        "bytes": 672003680,
        "sha256": "f18f594747e5317ab490cff9c06339c9cfb89acbe2f02ebc48a4e167bc23576d"
      },
      {
        "path": "mmproj-model-f16.gguf",
        "bytes": 1110117984,
        "sha256": "fb9cc047a3cdad5317fd8433a4aeda2d22f00f02ca4bd93b34ad84165b25a900"
      }
    ],
    "vendor": "面壁智能 · MiniCPM",
    "upstream": "openbmb/MiniCPM-V-4.7-1B",
    "highMemory": false
  },
  {
    "id": "minicpmv-46-q4",
    "name": "MiniCPM-V 4.6",
    "repo": "openbmb/MiniCPM-V-4.6-gguf",
    "revision": "afe9accb78d2995d214cd912920c9c92f4015faa",
    "format": "gguf",
    "capabilities": [
      "chat",
      "vision"
    ],
    "description": "小尺寸中文图片理解候选，自动配齐投影。合计约 1.64 GB；当前引擎兼容性和图像理解效果需实测。",
    "variant": "Q4_K_M + mmproj F16",
    "files": [
      {
        "path": "MiniCPM-V-4_6-Q4_K_M.gguf",
        "bytes": 529101504,
        "sha256": "6b0c74962c44bc6bf4b655b9b02c13eda9d5a0491543ae976d1ac18e4b7892e2"
      },
      {
        "path": "mmproj-model-f16.gguf",
        "bytes": 1108746944,
        "sha256": "ca931d861d0801d9003e50697cd764721a334107c0e0415a51168ee1938462de"
      }
    ],
    "vendor": "面壁智能 · MiniCPM",
    "upstream": "openbmb/MiniCPM-V-4.6",
    "highMemory": false
  },
  {
    "id": "sensevoice-small-int8",
    "name": "SenseVoice Small",
    "repo": "csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17",
    "revision": "2365baeacb507f821a0c8120fcee3d484dba7a07",
    "format": "sensevoice",
    "capabilities": [
      "speech"
    ],
    "description": "阿里中文语音识别，支持中文、粤语等语言。本地转写后可继续对话和整理记录，使用 sherpa-onnx 引擎。",
    "variant": "ONNX int8 · sherpa-onnx",
    "files": [
      {
        "path": "model.int8.onnx",
        "bytes": 239233841,
        "sha256": "c71f0ce00bec95b07744e116345e33d8cbbe08cef896382cf907bf4b51a2cd51"
      },
      {
        "path": "tokens.txt",
        "bytes": 315894,
        "sha256": "f449eb28dc567533d7fa59be34e2abca8784f771850c78a47fb731a31429a1dc"
      }
    ],
    "vendor": "阿里 · FunAudioLLM",
    "upstream": "FunAudioLLM/SenseVoiceSmall",
    "highMemory": false
  },
  {
    "id": "qwen3-asr-06b-int8",
    "name": "Qwen3-ASR 0.6B",
    "repo": "csukuangfj2/sherpa-onnx-qwen3-asr-0.6B-int8-2026-03-25",
    "revision": "68818b2313fe77bd06f6a7c5068ff3ef59d02b8a",
    "format": "qwen3asr",
    "capabilities": [
      "speech"
    ],
    "description": "通义千问语音识别模型，完整下载前端、编码器、解码器和分词器。约 0.99 GB 权重，使用 sherpa-onnx 引擎，不是语音合成模型。",
    "variant": "ONNX int8 · sherpa-onnx",
    "files": [
      {
        "path": "conv_frontend.onnx",
        "bytes": 44148281,
        "sha256": "d22dc4423e0940e49884e903d2ea2f7e5567c14fc1aed97e4e26d6b8f208ef9e"
      },
      {
        "path": "encoder.int8.onnx",
        "bytes": 182491662,
        "sha256": "60748d3e6744a57c9c91e1b17424a6c2990567e8adceb0783940c03ed98fa9d9"
      },
      {
        "path": "decoder.int8.onnx",
        "bytes": 755914231,
        "sha256": "4f6885be5959ae26af3089d38ee7972c5fafbeeb1cf8d5e76eab6d8b61ca5771"
      },
      {
        "path": "tokenizer/merges.txt",
        "bytes": 1671853,
        "sha256": "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5"
      },
      {
        "path": "tokenizer/tokenizer_config.json",
        "bytes": 12487,
        "sha256": "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c"
      },
      {
        "path": "tokenizer/vocab.json",
        "bytes": 2776833,
        "sha256": "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910"
      }
    ],
    "vendor": "阿里 · Qwen",
    "upstream": "Qwen/Qwen3-ASR-0.6B",
    "highMemory": false
  }
]''';
