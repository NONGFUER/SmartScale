import sherpa_onnx
import wave
import numpy as np
import os

model_dir = "/home/sjwu/matcha-icefall-zh-baker"

print("正在加载 Matcha-TTS (Baker) 模型...")
tts_config = sherpa_onnx.OfflineTtsConfig(
    model=sherpa_onnx.OfflineTtsModelConfig(
        matcha=sherpa_onnx.OfflineTtsMatchaModelConfig(
            acoustic_model=os.path.join(model_dir, "model-steps-3.onnx"),
            vocoder=os.path.join(model_dir, "vocos-22khz-univ.onnx"),
            lexicon=os.path.join(model_dir, "lexicon.txt"),
            tokens=os.path.join(model_dir, "tokens.txt"),
            data_dir=model_dir,          # fst / dict 辅助文件目录
            length_scale=0.98,            # 语速控制，<1 更快 >1 更慢
        ),
        provider="cpu",
        debug=False,
    ),
)

# 初始化引擎
tts = sherpa_onnx.OfflineTts(tts_config)

# 准备合成文本
text = "！！！土豆！！！"

print(f"正在合成语音: '{text}'")

# 合成音频（Matcha 无多说话人 sid 参数）
audio = tts.generate(text)

# 保存为 wav 音频文件
if audio.samples:
    with wave.open("output_matcha.wav", "w") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(audio.sample_rate)
        # 峰值归一化到最大不失真音量
        samples = np.array(audio.samples, dtype=np.float32)
        peak = np.max(np.abs(samples))
        if peak > 0:
            samples = samples / peak
        audio_data = (samples * 32767).astype(np.int16)
        f.writeframes(audio_data.tobytes())
    print(f"合成成功！采样率 {audio.sample_rate}Hz, 音频已保存为 output_matcha.wav")
else:
    print("合成失败，音频数据为空。")
