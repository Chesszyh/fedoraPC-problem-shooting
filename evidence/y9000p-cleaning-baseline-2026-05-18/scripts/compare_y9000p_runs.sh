#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 2 ]]; then
  printf 'Usage: %s <pre-run-dir> <post-run-dir>\n' "$0" >&2
  exit 2
fi

PRE="$1"
POST="$2"

if [[ ! -d "$PRE/raw" || ! -d "$POST/raw" ]]; then
  printf 'Both arguments must be run directories containing raw/.\n' >&2
  exit 2
fi

extract_identity() {
  local run="$1"
  {
    echo "## system"
    grep -E 'Manufacturer:|Product Name:|Version:|Serial Number:|UUID:|SKU Number:|Family:' "$run/raw/dmidecode_system.txt" 2>/dev/null || true
    echo "## baseboard"
    grep -E 'Manufacturer:|Product Name:|Version:|Serial Number:' "$run/raw/dmidecode_baseboard.txt" 2>/dev/null || true
    echo "## bios"
    grep -E 'Vendor:|Version:|Release Date:|BIOS Revision:|Firmware Revision:' "$run/raw/dmidecode_bios.txt" 2>/dev/null || true
    echo "## memory"
    grep -E 'Size:|Locator:|Type:|Speed:|Manufacturer:|Serial Number:|Part Number:|Configured Memory Speed:' "$run/raw/dmidecode_memory.txt" 2>/dev/null || true
    echo "## nvme"
    grep -E 'Model Number:|Serial Number:|Firmware Version:|Total NVM Capacity:' "$run/raw/smartctl_nvme0.txt" 2>/dev/null || true
    grep -E 'critical_warning|temperature|available_spare|percentage_used|power_cycles|power_on_hours|unsafe_shutdowns|media_errors|num_err_log_entries' "$run/raw/nvme_nvme0_smart_log.txt" 2>/dev/null || true
    echo "## nvidia"
    sed -n '1,3p' "$run/raw/nvidia_smi_query.txt" 2>/dev/null || true
    grep -E 'Product Name|GPU UUID|VBIOS Version|Device Id|Sub System Id|HW Thermal Slowdown|SW Thermal Slowdown|GPU Current Temp|Current Power Limit|Max Power Limit' "$run/raw/nvidia_smi_after.txt" 2>/dev/null || true
    echo "## battery"
    grep -E 'vendor:|model:|serial:|energy-full:|energy-full-design:|percentage:|capacity:' "$run/raw/upower_dump.txt" 2>/dev/null || true
  }
}

extract_perf() {
  local run="$1"
  {
    echo "## stress-ng cpu"
    grep -E 'cpu +[0-9]|successful run|turbo is disabled|governors set' "$run/raw/turbostat_cpu_stress.txt" 2>/dev/null || true
    grep -E 'Avg_MHz|^[0-9]+[[:space:]]+[0-9]' "$run/raw/turbostat_cpu_stress.txt" 2>/dev/null || true
    echo "## stress-ng memory"
    grep -E 'vm +[0-9]|successful run|using .* per stressor|available memory' "$run/raw/stress_ng_memory.txt" 2>/dev/null || true
    echo "## monitor peaks"
    awk '
      /Package id 0:/ {gsub(/[+°C]/,"",$4); if($4>pkg) pkg=$4}
      /Core [0-9]+:/ {gsub(/[+°C]/,"",$3); if($3>core) core=$3}
      /Composite:/ {gsub(/[+°C]/,"",$2); if($2>nvme) nvme=$2}
      /^[0-9]{4}\// {split($0,a,","); gsub(/^ +| +$/,"",a[5]); if(a[5]>gpu) gpu=a[5]}
      END {printf "package_max=%s\ncore_max=%s\nnvme_max=%s\ngpu_max=%s\n",pkg,core,nvme,gpu}
    ' "$run"/monitor/*.log 2>/dev/null || true
  }
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

extract_identity "$PRE" > "$TMP/pre.identity"
extract_identity "$POST" > "$TMP/post.identity"
extract_perf "$PRE" > "$TMP/pre.perf"
extract_perf "$POST" > "$TMP/post.perf"

echo "# Hardware identity diff"
diff -u "$TMP/pre.identity" "$TMP/post.identity" || true
echo
echo "# Performance and thermal diff"
diff -u "$TMP/pre.perf" "$TMP/post.perf" || true
