# NotchFlow 本地模型可行性探针

该探针用于验证模型可以只从本地目录加载，并通过 Apple MLX 在 Apple Silicon Mac 上离线生成中文回复。它不是最终用户界面。

## 当前选型

- 推理框架：MLX Swift LM 3.31.4
- 候选模型：`mlx-community/Qwen3-1.7B-4bit`
- 固定版本：`3b1b1768f8f8cf8351c712464f906e86c2b8269e`
- 权重 SHA-256：`0e86d9677e519323849eac1bc272caae88567a481ff188c431f70be543d9995f`
- 本地模型目录：`PrivateModelAssets/Qwen3-1.7B-4bit`

模型权重不提交 Git。正式打包阶段将模型目录、推理程序和 `mlx.metallib` 一并放入 App，用户无需安装 Ollama、Python 或其他运行环境。

## 运行

首次使用需由 Xcode 安装 Metal Toolchain。之后执行：

```zsh
./Tools/LocalModelProbe/build_and_run.sh
```

也可以传入模型目录和测试问题：

```zsh
./Tools/LocalModelProbe/build_and_run.sh \
  ./PrivateModelAssets/Qwen3-1.7B-4bit \
  "我刚完成了一件很难的事情！"
```
