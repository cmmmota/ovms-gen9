# ovms-gen9

OpenVINO Model Server image that works on **Intel Gen8/9 iGPUs** (UHD 630 /
UHD 620 / HD 530) in this homelab's three older nodes.

## Why this exists

The stock `openvino/model_server:*-gpu` image bundles Intel's modern (26.x)
compute runtime, which [dropped Gen8–11][drop]. On these chips any model load
dies with `Requested function unsupported by HW`. Intel's answer is a parallel
`legacy1` driver stack (IGC 1.0.x + compute-runtime 24.x); the ICD loader
selects legacy vs modern per PCI ID, so one image serves every GPU in the
fleet. This is the same combination Immich ML runs daily on the same hardware
— see [the Immich install script][immich-script] the Dockerfile mirrors.

Built for [k8s_homelab issue #1519][issue]: move Whisper STT off the RTX 2080 Ti
onto sancho's UHD 630 to free ~1.2 GiB of VRAM for stable-diffusion-webui.

[drop]: https://github.com/intel/compute-runtime/releases
[immich-script]: https://github.com/immich-app/immich/blob/main/machine-learning/scripts/install-intel-runtime.sh
[issue]: https://github.com/cmmmota/k8s_homelab/issues/1519

## Usage (kubernetes)

The deployment lives in `cmmmota/k8s_homelab` under `kubernetes/apps/ai/wyoming-asr/`.
Equivalent bare-docker launch:

```bash
docker run -d --name ovms-gen9 \
  --device /dev/dri \
  -p 8000:8000 \
  -v $PWD/models:/models \
  ghcr.io/cmmmota/ovms-gen9:latest \
  --model_name whisper-large-v3-turbo-int8-ov \
  --model_repository_path /models \
  --source_model OpenVINO/whisper-large-v3-turbo-int8-ov \
  --target_device GPU \
  --port 8000
```

First start downloads the model (~800 MB int8 / ~1.6 GB fp16) from Hugging Face
into the mounted models dir. Endpoint is OpenAI-compatible:

```bash
curl -F model=whisper-large-v3-turbo-int8-ov -F file=@sample.wav \
  http://localhost:8000/v1/audio/transcriptions
```

## Benchmark

`./bench_asr.sh --url http://localhost:8000/v1 --runs 10 en.wav pt.wav`
prints min/p50/p95/max per file. Baselines and the accept/abort gate are in
the script header and issue #1519. Use **PT** clips for the decision — EN
whisper was never the bottleneck.

## Stretch: Kokoro TTS

The same image serves `OpenVINO/Kokoro-82M-int8-ov` on CPU
(`--target_device CPU --model_version_policy '{"all": {}}'` with the voice
subgraphs). If OVMS beats the current Kokoro-FastAPI pod (1.8 s/short
sentence, sancho CPU), TTS can ride along in the same container. Measure
before committing to it.

## Image tags

Same scheme as `cmmmota/hermes-with-tools`, so the cluster can pin a semver tag
by digest and Renovate can bump it:

- `2026.4.1` — floats to the newest build on that OVMS base; k8s_homelab pins
  this tag with a digest and Renovate bumps it when the base image moves
- `2026.4.1-<sha>` — immutable, exact build; use when you want a deployment
  that provably never moves
- `<sha>` (short), `main`, `latest` — convenience/rolling
