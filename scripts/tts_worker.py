import sherpa_onnx
import wave
import numpy as np

print("正在加载小雅模型...")
tts_config = sherpa_onnx.OfflineTtsConfig(
    model=sherpa_onnx.OfflineTtsModelConfig(
        vits=sherpa_onnx.OfflineTtsVitsModelConfig(
            # 这里的路径刚好对应你解压出来的文件夹
            model="/home/sjwu/vits-piper-zh_CN-xiao_ya-medium/zh_CN-xiao_ya-medium.onnx",
            lexicon="/home/sjwu/vits-piper-zh_CN-xiao_ya-medium/lexicon.txt",
            tokens="/home/sjwu/vits-piper-zh_CN-xiao_ya-medium/tokens.txt",
            length_scale=1.2,
        ),
        provider="cpu",
        debug=False,
    )
)

tts = sherpa_onnx.OfflineTts(tts_config)

text = "土豆"
print(f"正在合成语音: '{text}'")
audio = tts.generate(text)

# 保存为 wav 音频文件
with wave.open("output.wav", "w") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(audio.sample_rate)
    audio_data = (np.array(audio.samples) * 32767).astype(np.int16)
    f.writeframes(audio_data.tobytes())

print("合成成功！音频已保存为当前目录下的 output.wav")