#!/usr/bin/env bash
set -Eeuo pipefail

BASE_DIR="${1:-$PWD/y9000p-cleaning-snapshot}"
LABEL="${2:-run}"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$BASE_DIR/runs/${LABEL}-${STAMP}"
RAW_DIR="$RUN_DIR/raw"
MON_DIR="$RUN_DIR/monitor"
mkdir -p "$RAW_DIR" "$MON_DIR"

export LC_ALL=C
export LANG=C

COMMAND_LOG="$RUN_DIR/command-index.tsv"
SUMMARY="$RUN_DIR/summary.md"
STATUS_LOG="$RUN_DIR/status.log"

printf 'file\tstatus\tduration_seconds\tcommand\n' > "$COMMAND_LOG"

log() {
  printf '[%s] %s\n' "$(date -Is)" "$*" | tee -a "$STATUS_LOG"
}

have() {
  command -v "$1" >/dev/null 2>&1
}

sudo_cmd=()
if sudo -n true >/dev/null 2>&1; then
  sudo_cmd=(sudo -n)
else
  log "sudo -n is not available; privileged commands will be skipped or fail in raw output."
fi

run_cmd() {
  local name="$1"
  shift
  local outfile="$RAW_DIR/${name}.txt"
  local start end status
  start="$(date +%s)"
  log "RUN $name: $*"
  set +e
  "$@" >"$outfile" 2>&1
  status=$?
  set -e
  end="$(date +%s)"
  printf '%s\t%s\t%s\t%q ' "$(basename "$outfile")" "$status" "$((end - start))" "$1" >> "$COMMAND_LOG"
  shift || true
  printf '%q ' "$@" >> "$COMMAND_LOG"
  printf '\n' >> "$COMMAND_LOG"
  return 0
}

run_shell() {
  local name="$1"
  local script="$2"
  run_cmd "$name" bash -lc "$script"
}

copy_file() {
  local src="$1"
  local name="$2"
  if [[ -r "$src" ]]; then
    run_cmd "$name" cp -a "$src" "$RAW_DIR/${name}.copy"
  else
    printf 'not readable: %s\n' "$src" > "$RAW_DIR/${name}.txt"
    printf '%s\t%s\t%s\t%s\n' "${name}.txt" "skip" "0" "copy $src" >> "$COMMAND_LOG"
  fi
}

snapshot_sensors_loop() {
  local seconds="$1"
  local interval="$2"
  local prefix="$3"
  local out="$MON_DIR/${prefix}.tsv"
  local end=$((SECONDS + seconds))
  printf 'timestamp\tsection\tvalue\n' > "$out"
  while (( SECONDS < end )); do
    {
      printf '### %s sensors\n' "$(date -Is)"
      sensors 2>&1 || true
      printf '### %s nvidia\n' "$(date -Is)"
      if have nvidia-smi; then
        nvidia-smi --query-gpu=timestamp,name,uuid,pstate,temperature.gpu,power.draw,power.limit,clocks.gr,clocks.mem,utilization.gpu,utilization.memory,memory.used --format=csv,noheader,nounits 2>&1 || true
      fi
      printf '### %s cpu_frequency\n' "$(date -Is)"
      grep -H . /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | head -64 || true
    } >> "$MON_DIR/${prefix}.log"
    sleep "$interval"
  done
}

log "snapshot directory: $RUN_DIR"

cat > "$SUMMARY" <<EOF
# Y9000P 2023 Health Snapshot

- Run label: \`$LABEL\`
- Start time: \`$(date -Is)\`
- Host: \`$(hostname)\`
- Kernel: \`$(uname -r)\`
- Output directory: \`$RUN_DIR\`

This directory preserves raw command output for pre/post cleaning comparison.

EOF

run_cmd date date -Is
run_cmd uname uname -a
copy_file /etc/os-release os-release
copy_file /proc/cmdline kernel-cmdline
run_cmd uptime uptime
run_cmd who who -a
run_cmd free free -h
run_cmd swapon swapon --show
run_cmd lsblk lsblk -O
run_cmd findmnt findmnt -R /
run_cmd blkid "${sudo_cmd[@]}" blkid
run_cmd lscpu lscpu
run_cmd lscpu_extended lscpu -e
run_cmd cpuinfo bash -lc "grep -E '^(processor|model name|microcode|cpu MHz|cache size|physical id|core id|siblings|cpu cores)' /proc/cpuinfo"
run_shell cpu_governors "grep -H . /sys/devices/system/cpu/cpu*/cpufreq/scaling_{driver,governor,min_freq,max_freq,cur_freq} 2>/dev/null | sort"

if have fastfetch; then run_cmd fastfetch fastfetch; fi
if have inxi; then run_cmd inxi_full inxi -Fxxxz; fi

run_cmd dmidecode_all "${sudo_cmd[@]}" dmidecode
run_cmd dmidecode_system "${sudo_cmd[@]}" dmidecode -t system
run_cmd dmidecode_baseboard "${sudo_cmd[@]}" dmidecode -t baseboard
run_cmd dmidecode_bios "${sudo_cmd[@]}" dmidecode -t bios
run_cmd dmidecode_processor "${sudo_cmd[@]}" dmidecode -t processor
run_cmd dmidecode_memory "${sudo_cmd[@]}" dmidecode -t memory

run_cmd lspci_nn lspci -nn
run_cmd lspci_vv "${sudo_cmd[@]}" lspci -nnvv
run_cmd lsusb lsusb
run_cmd lsusb_tree lsusb -tv
run_cmd lsusb_verbose "${sudo_cmd[@]}" lsusb -v

if have sensors; then
  run_cmd sensors sensors
  run_cmd sensors_json sensors -j
fi
run_shell thermal_sysfs "for z in /sys/class/thermal/thermal_zone*; do echo '###' \$z; grep -H . \$z/type \$z/temp \$z/trip_point_* 2>/dev/null; done"
run_shell cooling_sysfs "for c in /sys/class/thermal/cooling_device*; do echo '###' \$c; grep -H . \$c/type \$c/cur_state \$c/max_state 2>/dev/null; done"
run_shell hwmon_sysfs "for h in /sys/class/hwmon/hwmon*; do echo '###' \$h; grep -H . \$h/name \$h/*_label \$h/temp*_input \$h/fan*_input \$h/pwm* 2>/dev/null; done"

if have nvidia-smi; then
  run_cmd nvidia_smi nvidia-smi
  run_cmd nvidia_smi_query nvidia-smi --query-gpu=name,uuid,gpu_bus_id,pci.device_id,pci.sub_device_id,vbios_version,driver_version,pstate,temperature.gpu,power.draw,power.limit,clocks.gr,clocks.mem,memory.total,memory.used --format=csv
  run_cmd nvidia_smi_q nvidia-smi -q
  run_cmd nvidia_smi_q_xml nvidia-smi -q -x
  run_cmd nvidia_smi_supported_clocks nvidia-smi -q -d SUPPORTED_CLOCKS
fi
if have glxinfo; then
  run_cmd glxinfo_summary glxinfo -B
fi

if have nvme; then
  run_cmd nvme_list "${sudo_cmd[@]}" nvme list
  for dev in /dev/nvme[0-9]; do
    [[ -e "$dev" ]] || continue
    safe="${dev#/dev/}"
    run_cmd "nvme_${safe}_id_ctrl" "${sudo_cmd[@]}" nvme id-ctrl "$dev"
    run_cmd "nvme_${safe}_smart_log" "${sudo_cmd[@]}" nvme smart-log "$dev"
    run_cmd "nvme_${safe}_error_log" "${sudo_cmd[@]}" nvme error-log "$dev"
  done
fi
if have smartctl; then
  for dev in /dev/nvme[0-9]; do
    [[ -e "$dev" ]] || continue
    safe="${dev#/dev/}"
    run_cmd "smartctl_${safe}" "${sudo_cmd[@]}" smartctl -a "$dev"
  done
fi

if have upower; then
  run_cmd upower_devices upower -e
  run_shell upower_dump "for d in \$(upower -e); do echo '###' \$d; upower -i \$d; done"
fi
if have tlp-stat; then
  run_cmd tlp_stat_all "${sudo_cmd[@]}" tlp-stat
  run_cmd tlp_stat_battery "${sudo_cmd[@]}" tlp-stat -b
fi

if have fwupdmgr; then run_cmd fwupdmgr_devices fwupdmgr get-devices; fi
if have rpm; then
  run_shell rpm_key_packages "rpm -qa | sort | grep -Ei '^(kernel|nvidia|akmod|kmod|xorg-x11-drv-nvidia|mesa|vulkan|hyprland|linux-firmware|tlp|lm_sensors|stress-ng|nvme-cli|smartmontools)'"
fi
run_cmd journal_current_boot_errors journalctl -b -p warning..alert --no-pager
run_cmd dmesg_errors "${sudo_cmd[@]}" dmesg -T --level=err,warn

log "idle monitoring for 60 seconds"
snapshot_sensors_loop 60 5 idle

if have stress-ng; then
  log "CPU stress test: 180 seconds with sensor monitoring"
  snapshot_sensors_loop 190 5 cpu_stress &
  mon_pid=$!
  if have turbostat; then
    run_cmd turbostat_cpu_stress "${sudo_cmd[@]}" turbostat --quiet --Summary --interval 5 --num_iterations 36 --show Busy%,Bzy_MHz,Avg_MHz,TSC_MHz,CPU%c1,CPU%c6,CoreTmp,PkgTmp,PkgWatt,GFXWatt,RAMWatt -- stress-ng --cpu 0 --cpu-method matrixprod --metrics-brief --timeout 180s
  else
    run_cmd stress_ng_cpu stress-ng --cpu 0 --cpu-method matrixprod --metrics-brief --timeout 180s
  fi
  wait "$mon_pid" || true
fi

if have stress-ng; then
  log "short memory stress test: 90 seconds"
  snapshot_sensors_loop 100 5 memory_stress &
  mon_pid=$!
  run_cmd stress_ng_memory stress-ng --vm 2 --vm-bytes 70% --metrics-brief --timeout 90s
  wait "$mon_pid" || true
fi

run_cmd sensors_after sensors
if have nvidia-smi; then run_cmd nvidia_smi_after nvidia-smi -q; fi

sha256sum "$RAW_DIR"/* "$MON_DIR"/* 2>/dev/null > "$RUN_DIR/SHA256SUMS" || true

cat >> "$SUMMARY" <<EOF

## Completion

- End time: \`$(date -Is)\`
- Raw outputs: \`$RAW_DIR\`
- Monitor logs: \`$MON_DIR\`
- Command index: \`$COMMAND_LOG\`
- Checksums: \`$RUN_DIR/SHA256SUMS\`

## Compare after cleaning

Run the same script after cleaning:

\`\`\`bash
$0 "$BASE_DIR" post-clean
\`\`\`

Important comparison anchors:

- Hardware identity: DMI serials, BIOS version, baseboard, memory module part/serial, NVMe model/serial, NVIDIA UUID/VBIOS/subsystem id.
- Cooling: idle and CPU-stress package temperature, thermal slowdown flags, turbostat MHz/Watt behavior, sensor monitor logs.
- Health: NVMe SMART critical warnings, media errors, unsafe shutdowns, battery state, kernel warnings.
EOF

log "snapshot complete: $RUN_DIR"
printf '%s\n' "$RUN_DIR"
