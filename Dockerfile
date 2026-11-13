# Image:
#   ghcr.io/cmmmota/ovms-gen9
# Purpose:
#   OpenVINO Model Server usable on Intel Gen8/9 iGPUs (UHD 630 on sancho,
#   UHD 620 on serf, HD 530 on steward). The stock -gpu image ships the 26.x
#   compute runtime, which dropped Gen8-11 support: models fail to load with
#   "Requested function unsupported by HW". This image layers Intel's
#   legacy1 runtime on top, exactly the combination Immich ML validates daily
#   on these same nodes:
#   https://github.com/immich-app/immich/blob/main/machine-learning/scripts/install-intel-runtime.sh
#   The ICD loader picks the legacy driver for legacy PCI IDs and the modern
#   one for newer GPUs, so both coexist in one image.
#
# The deb pins below mirror Immich's script line for line; when renovate
# bumps them, bump the base image at the same time so the two runtimes stay
# a tested pair.

# openvino/model_server, -gpu flavour for OpenCL. Audio endpoints
# (/v1 & /v3 audio/transcriptions, /v3 audio/speech) are OpenAI-compatible
# since 2026.3, which is what the wyoming_openai bridge speaks.
FROM openvino/model_server:2026.4.1-gpu

# install-intel-runtime.sh verbatim (dpkg -i of this set; the modern-IGC
# packages are igc-*-2 and do not clash with the legacy igc-* ones).
# renovate: datasource=github-releases depName=intel/compute-runtime
RUN curl -fSsLO https://github.com/intel/compute-runtime/releases/download/26.35.39758.10/libigdgmm12_22.10.0_amd64.deb \
 # renovate: datasource=github-releases depName=intel/compute-runtime
 && curl -fSsLO https://github.com/intel/compute-runtime/releases/download/26.35.39758.10/intel-opencl-icd_26.35.39758.10-0_amd64.deb \
 # renovate: datasource=github-releases depName=intel/compute-runtime versioning=semver-coerced
 && curl -fSsLO https://github.com/intel/compute-runtime/releases/download/24.35.30872.36/intel-opencl-icd-legacy1_24.35.30872.36_amd64.deb \
 # renovate: datasource=github-releases depName=intel/intel-graphics-compiler versioning=regex:^v(?<version>.*)$
 && curl -fSsLO https://github.com/intel/intel-graphics-compiler/releases/download/v2.41.5/intel-igc-core-2_2.41.5+22716_amd64.deb \
 # renovate: datasource=github-releases depName=intel/intel-graphics-compiler versioning=regex:^v(?<version>.*)$
 && curl -fSsLO https://github.com/intel/intel-graphics-compiler/releases/download/v2.41.5/intel-igc-opencl-2_2.41.5+22716_amd64.deb \
 # renovate: datasource=github-releases depName=intel/intel-graphics-compiler versioning=regex:^igc-(?<version>.*)$
 && curl -fSsLO https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17537.24/intel-igc-core_1.0.17537.24_amd64.deb \
 # renovate: datasource=github-releases depName=intel/intel-graphics-compiler versioning=regex:^igc-(?<version>.*)$
 && curl -fSsLO https://github.com/intel/intel-graphics-compiler/releases/download/igc-1.0.17537.24/intel-igc-opencl_1.0.17537.24_amd64.deb \
 && dpkg -i ./*.deb \
 && rm -f ./*.deb

# The base image runs ovms as uid 5000, a one-off user that matches nothing on
# the cluster. Everything i915 in this homelab (immich ML) runs as 1000:1000
# against gpu.intel.com/i915 allocations and writes to fsGroup-1000 volumes,
# so adopt 1000 here too and evict any uid 1000 squatter in the base.
RUN set -eux; \
    if getent passwd 1000 >/dev/null; then \
      squatter="$(getent passwd 1000 | cut -d: -f1)"; \
      userdel "$squatter" || true; \
    fi; \
    groupmod -o -g 1000 ovms || true; \
    usermod -o -u 1000 -g 1000 ovms || true; \
    chown -R ovms:ovms /home/ovms

USER 1000:1000
WORKDIR /models

# Entrypoint inherited: /ovms/bin/ovms. Launch args and the kubernetes wiring
# live in cmmmota/k8s_homelab kubernetes/apps/ai/wyoming-asr/ ; README.md has
# the one-line docker equivalent.
