# Paimon Pal 原创伙伴声线实验

本实验仅验证 Apple Silicon 上的本地语音生成能力，不接入当前 App。

- 模型：`mlx-community/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit`
- 输出：三个使用相同台词的原创声线候选
- 边界：不使用现有角色或真人的录音，不在提示词中指定模仿对象
- 验收：人工试听音色，同时记录加载时间、生成时间、音频长度和峰值内存

本机执行：

```bash
source .tts-lab-venv/bin/activate
python Tools/TTSVoiceLab/generate_candidates.py \
  --model PrivateTTSAssets/Qwen3-TTS-12Hz-1.7B-VoiceDesign-4bit \
  --output PrivateTTSAssets/voice-candidates
```

`PrivateTTSAssets/` 和 `.tts-lab-venv/` 均被 Git 忽略，不会进入正式源码或安装包。
