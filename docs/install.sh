#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

# JetPack 6 / L4T R36 (Ubuntu 22.04, Orin). Never flashes the device.
root=/opt/oqllm-jetson
release=$root/0.1.0
cache=/var/cache/oqllm-jetson
base=${OQLLM_ASSET_BASE:-https://get.oqllm.com}
ollama_url=https://github.com/ollama/ollama/releases/download/v0.40.17
speech_name=sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-560ms-int8-2026-06-11
model=Bielik-1.5B-v3.0-Instruct.Q8_0.gguf
private_sha=59da6368073024a7b89b0759a49b806a3f42ec8a
mode=${1:-install}

die() { echo "Błąd: $*" >&2; exit 1; }

preflight() {
    [[ $(uname -m) == aarch64 ]] || die "Uruchom na Jetsonie Orin (ARM64)."
    grep -aq 'tegra234' /proc/device-tree/compatible || die "Wymagany moduł Orin (Tegra234)."
    grep -Eq '^# R36\b' /etc/nv_tegra_release || die "Wymagany JetPack 6 / L4T R36."
    . /etc/os-release
    [[ $ID == ubuntu && $VERSION_ID == 22.04 ]] || die "Wymagane Ubuntu 22.04 z JetPack 6."
    [[ -d /run/systemd/system ]] || die "Wymagany działający systemd."
    awk '/MemTotal:/ {exit ($2 < 6800000)}' /proc/meminfo || die "Wymagany Orin z co najmniej 8 GB RAM."
    if [[ ! -f $release/.prepared ]]; then
        local available
        available=$(df -Pk /opt | awk 'END {print $4}')
        (( available >= 14*1024*1024 )) || die "Zwolnij 14 GiB przestrzeni dla instalacji."
    fi
    for service in ollama api stt oql; do
        local unit=/etc/systemd/system/oqllm-jetson-$service.service
        if [[ -e $unit ]] && ! grep -Fxq '# Managed by get.oqllm.com' "$unit"; then
            die "Istnieje obca jednostka $unit."
        fi
    done
    echo 'Jetson Orin / JetPack 6 — wymagania spełnione.'
}

fetch() {
    local url=$1 out=$2 hash=$3
    if [[ -f $out ]] && printf '%s  %s\n' "$hash" "$out" | sha256sum --check --status; then
        return
    fi
    echo "Pobieram ${out##*/} ..."
    curl --fail --location --show-error --silent --retry 3 --connect-timeout 15 \
        --proto '=https' --proto-redir '=https' --output "$out.part" "$url"
    printf '%s  %s\n' "$hash" "$out.part" | sha256sum --check --status || die "Błędna suma SHA-256: ${out##*/}"
    mv -f -- "$out.part" "$out"
}

unit() {
    local name=$1 command=$2 extra=$3 dest=/etc/systemd/system/oqllm-jetson-$1.service
    cat > "$dest.new" <<UNIT
# Managed by get.oqllm.com
[Unit]
Description=OQLLM Jetson $name
After=network.target
[Service]
DynamicUser=yes
StateDirectory=oqllm-jetson-$name
Environment=HOME=/var/lib/oqllm-jetson-$name
Environment=PYTHONDONTWRITEBYTECODE=1
Environment=OLLAMA_HOST=127.0.0.1:11439
Environment=OLLAMA_NO_CLOUD=1
Environment=OLLAMA_MAX_LOADED_MODELS=1
Environment=OLLAMA_NUM_PARALLEL=1
NoNewPrivileges=yes
ProtectSystem=strict
PrivateTmp=yes
IPAddressDeny=any
IPAddressAllow=localhost
$extra
ExecStart=$command
Restart=on-failure
RestartSec=3
[Install]
WantedBy=multi-user.target
UNIT
    mv -f -- "$dest.new" "$dest"
}

wait_http() {
    local url=$1
    for ((i=0;i<90;i++)); do
        if curl -fsS --max-time 2 "$url" >/dev/null 2>&1; then return; fi
        sleep 1
    done
    die "Usługa nie odpowiada: $url. Sprawdź journalctl -u 'oqllm-jetson-*'."
}

prepare() {
    export UV_PYTHON_INSTALL_DIR=$root/python
    local assets=$release/runtime
    install -d -m 755 "$assets" "$release/asr"
    fetch "$base/runtime/chat.py" "$assets/chat.py" d8bde45ddd12d95bbc9c857707fa62f5f8b2743862d5e5cb148f8d9e22a2e834
    fetch "$base/runtime/speech.py" "$assets/speech.py" 0121b6329264da69156f05ef7f65c40d99af72b6b3b907353274d954703e3007
    fetch "$base/runtime/listen.py" "$assets/listen.py" 32a6147bd9879f778647ac15326a123597887f98a47b77552b63ea4e4f3570c0
    fetch "$base/runtime/Modelfile" "$cache/Modelfile" 18a1bd098a52834a571577cf5661b72a4aa3c966d4bc0fc31b80fd759820ed81
    fetch "https://huggingface.co/speakleash/Bielik-1.5B-v3.0-Instruct-GGUF/resolve/d3f43577b7b23c3e8a9671e1b35d26d74736277f/$model" "$cache/$model" 014fc8a22eb85c557e395476071bacd14dd8c8a69dedb96e5dd17e8bb7cee9c3
    if [[ ! -f $release/.prepared ]]; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends zstd bzip2 ca-certificates git alsa-utils libgomp1
        fetch "$ollama_url/ollama-linux-arm64.tar.zst" "$cache/ollama.tar.zst" 0ec632480057cef6300459d1fa7dbbb3fc188b9a7d56cd0b0a72d05927d90ecc
        fetch "$ollama_url/ollama-linux-arm64-jetpack6.tar.zst" "$cache/jetpack6.tar.zst" dae309dd57daf78de5ebbb47e5d2fe69c3eb84b31ea7f2dc7778a2f689d38109
        tar --zstd -xf "$cache/ollama.tar.zst" -C "$release"
        tar --zstd -xf "$cache/jetpack6.tar.zst" -C "$release"
        fetch "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$speech_name.tar.bz2" "$cache/asr.tar.bz2" c6bf5e0df765f9d5b43bc9e0536d4b4b3e7d40bdf5ecf13e45f134c51c05ae3a
        tar -xjf "$cache/asr.tar.bz2" --strip-components=1 -C "$release/asr"
        fetch https://github.com/astral-sh/uv/releases/download/0.9.8/uv-aarch64-unknown-linux-gnu.tar.gz "$cache/uv.tar.gz" 8dc203a27c99f721545adc531279f0486ea3deb77c951a051e6bb9ea1d588a71
        tar -xzf "$cache/uv.tar.gz" -C "$release" --strip-components=1 uv-aarch64-unknown-linux-gnu/uv
        fetch https://github.com/subactor/subllm/archive/7d195b8ea0c341776129bc7b09b11c8b8a5c2916.tar.gz "$cache/subllm.tar.gz" d935337a245f29bd596a6520dd5c26b4c8bd1eaebc63752cfa3156eb5a1a6e55
        "$release/uv" python install 3.11.14
        [[ -x $release/venv/bin/python ]] || "$release/uv" venv --managed-python --python 3.11.14 "$release/venv"
        "$release/uv" pip install --python "$release/venv/bin/python" "$cache/subllm.tar.gz" 'numpy==1.26.4' 'websockets==15.0.1' 'sherpa-onnx==2.0.2'
        "$release/venv/bin/python" -c 'import subllm.proxy, sherpa_onnx, numpy, websockets'
        touch "$release/.prepared"
    fi
}

main() {
    case "$mode" in
        -h|--help) echo 'Użycie: sudo bash install.sh [--check | --with-oql]. Opcja OQL wymaga gh z dostępem do oqllm/oqllm.'; return ;;
        install|--check|--with-oql) ;;
        *) die "Nieznana opcja $mode" ;;
    esac
    preflight
    [[ $mode != --check ]] || return 0
    [[ $EUID == 0 ]] || die "Uruchom instalator przez sudo."
    install -d -m 755 "$root" "$cache"
    exec 9>"$root/install.lock"
    flock -n 9 || die 'Inna instalacja jest w toku.'
    if [[ $mode == --with-oql ]]; then
        command -v gh >/dev/null || die 'Zainstaluj GitHub CLI i zaloguj się kontem z dostępem do oqllm/oqllm.'
        install -m 600 /dev/null "$cache/oqllm.tar.gz.part"
        sudo -H -u "${SUDO_USER:-root}" gh api "repos/oqllm/oqllm/tarball/$private_sha" > "$cache/oqllm.tar.gz.part"
        mv "$cache/oqllm.tar.gz.part" "$cache/oqllm.tar.gz"
    fi
    prepare
    if [[ $mode == --with-oql ]]; then
        [[ -x $release/oql/bin/python ]] || "$release/uv" venv --managed-python --python 3.11.14 "$release/oql"
        "$release/uv" pip install --python "$release/oql/bin/python" "$cache/oqllm.tar.gz"
        "$release/oql/bin/oqllm" serve --help >/dev/null
    fi
    # All three ports must belong to our services or be available on first start.
    local port name
    local -a ports=('11439 ollama' '11437 api' '11438 stt')
    if [[ $mode == --with-oql ]]; then ports+=('11440 oql'); fi
    for pair in "${ports[@]}"; do
        read -r port name <<< "$pair"
        if ss -Hltn "sport = :$port" | grep -q . && ! systemctl is-active -q "oqllm-jetson-$name"; then die "Port $port jest zajęty."; fi
    done
    local groups=''
    for group in video render; do if getent group "$group" >/dev/null; then groups+=" $group"; fi; done
    unit ollama "$release/bin/ollama serve" "SupplementaryGroups=$groups"
    unit api "$release/venv/bin/python $release/runtime/chat.py" ''
    unit stt "$release/venv/bin/python $release/runtime/speech.py $release/asr" ''
    if [[ $mode == --with-oql ]]; then unit oql "$release/oql/bin/oqllm serve --port 11440 --ollama-upstream http://127.0.0.1:11439" ''; fi
    systemctl daemon-reload
    systemctl enable --now oqllm-jetson-ollama
    wait_http http://127.0.0.1:11439/api/tags
    export OLLAMA_HOST=127.0.0.1:11439
    (cd "$cache" && "$release/bin/ollama" create bielik -f Modelfile)
    systemctl enable --now oqllm-jetson-api oqllm-jetson-stt
    wait_http http://127.0.0.1:11437/health
    "$release/venv/bin/python" - <<'PY'
import time
from websockets.sync.client import connect
for attempt in range(90):
    try:
        with connect('ws://127.0.0.1:11438/v1/listen', open_timeout=2) as ws:
            ws.send('end')
            import json
            assert json.loads(ws.recv(timeout=15))['type'] == 'final'
        break
    except OSError:
        time.sleep(1)
else:
    raise SystemExit("STT nie odpowiada. Sprawdź journalctl -u oqllm-jetson-stt.")
PY
    if [[ $mode == --with-oql ]]; then systemctl enable --now oqllm-jetson-oql; wait_http http://127.0.0.1:11440/health; fi
    echo 'Gotowe. Bielik: http://127.0.0.1:11437/v1    STT: ws://127.0.0.1:11438/v1/listen'
}
main "$@"
