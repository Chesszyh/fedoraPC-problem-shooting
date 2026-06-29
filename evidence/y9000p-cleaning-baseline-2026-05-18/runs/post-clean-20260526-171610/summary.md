# Y9000P 2023 Health Snapshot

- Run label: `post-clean`
- Start time: `2026-05-26T17:16:10+08:00`
- Host: `chesszyh`
- Kernel: `7.0.9-105.fc43.x86_64`
- Output directory: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610`

This directory preserves raw command output for pre/post cleaning comparison.


## Completion

- End time: `2026-05-26T17:22:18+08:00`
- Raw outputs: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610/raw`
- Monitor logs: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610/monitor`
- Command index: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610/command-index.tsv`
- Checksums: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610/SHA256SUMS`

## Compare after cleaning

Run the same script after cleaning:

```bash
/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/y9000p_health_snapshot.sh "/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18" post-clean
```

Important comparison anchors:

- Hardware identity: DMI serials, BIOS version, baseboard, memory module part/serial, NVMe model/serial, NVIDIA UUID/VBIOS/subsystem id.
- Cooling: idle and CPU-stress package temperature, thermal slowdown flags, turbostat MHz/Watt behavior, sensor moniztor logs.
- Health: NVMe SMART critical warnings, media errors, unsafe shutdowns, battery state, kernel warnings.
