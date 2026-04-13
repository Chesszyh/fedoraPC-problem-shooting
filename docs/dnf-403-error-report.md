# Fedora 43 DNF Repository Metadata Download Failure Report

## 1. Problem Description
Running `sudo dnf upgrade --refresh` failed with a **403 Forbidden** error when attempting to fetch metadata from the Tsinghua University (TUNA) mirror for Fedora 43.

**Error Message:**
> Status code: 403 for https://mirrors.tuna.tsinghua.edu.cn/fedora/updates/43/Everything/x86_64/repodata/...
> Failed to download metadata for repository "updates": Cannot download, all mirrors were already tried without success.

## 2. Root Cause Analysis
The issue was localized to the **Tsinghua (TUNA)** mirror station. Specifically, the DNF client was unable to access required metadata files (repomd.xml and associated blobs) because the server responded with a 403 status code. This typically indicates synchronization issues on the mirror server or temporary access restrictions for specific repository versions (Fedora 43).

## 3. Solution
The core strategy was to switch from a hardcoded `baseurl` (pointing directly to the TUNA mirror) back to the official Fedora **metalink** system. This system allows the DNF client to automatically discover and use the most reliable and geographically close mirrors from the global Fedora mirror network, bypassing the problematic TUNA mirror.

### Steps Taken:
1. **Repository Configuration Adjustment:**
   - Modified `/etc/yum.repos.d/fedora.repo` and `/etc/yum.repos.d/fedora-updates.repo`.
   - Commented out the lines starting with `baseurl=https://mirrors.tuna.tsinghua.edu.cn`.
   - Enabled the official `metalink` lines by removing the `#` prefix.

2. **Cache Refresh:**
   - Executed `sudo dnf clean all` to remove stale/corrupted metadata.
   - Executed `sudo dnf makecache --refresh` to rebuild the cache using the new metalink configuration.

## 4. Verification & Status
After the configuration change, `dnf check-update` successfully contacted the Fedora infrastructure, retrieved metadata from working mirrors, and identified over 100 pending updates.

**Current Status:** Resolved. System is ready for `sudo dnf upgrade`.

---
*Report Generated: 2026-03-09*
