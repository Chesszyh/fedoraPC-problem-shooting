# Y9000P 2023 Health Snapshot

- Run label: `pre-clean`
- Start time: `2026-05-18T22:09:13+08:00`
- Host: `chesszyh`
- Kernel: `7.0.4-100.fc43.x86_64`
- Output directory: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913`

This directory preserves raw command output for pre/post cleaning comparison.


## Completion

- End time: `2026-05-18T22:15:26+08:00`
- Raw outputs: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/raw`
- Monitor logs: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/monitor`
- Command index: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/command-index.tsv`
- Checksums: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/SHA256SUMS`

## Compare after cleaning

Run the same script after cleaning:

```bash
/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/y9000p_health_snapshot.sh "/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18" post-clean
```

Important comparison anchors:

- Hardware identity: DMI serials, BIOS version, baseboard, memory module part/serial, NVMe model/serial, NVIDIA UUID/VBIOS/subsystem id.
- Cooling: idle and CPU-stress package temperature, thermal slowdown flags, turbostat MHz/Watt behavior, sensor monitor logs.
- Health: NVMe SMART critical warnings, media errors, unsafe shutdowns, battery state, kernel warnings.
