# mac-ssd-rescue

<p align="center">
  <strong>Reclaim SSD space on a Mac by migrating Xcode artifacts to an external USB drive</strong>
</p>

<p align="center">
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-ffd60a?style=flat-square" alt="License: MIT"/></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/macOS-Sonoma_|_Sequoia_|_Tahoe-0071e3?style=flat-square" alt="macOS"/></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/Bash-5.0+-4eaa25?style=flat-square" alt="Bash 5.0+"/></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/Dependencies-zero-2ea44f?style=flat-square" alt="Zero Dependencies"/></a>
  <br/>
  <a href="https://github.com/sponsors/Viniciuscarvalho"><img src="https://img.shields.io/badge/Sponsor-❤-ea4aaa?style=flat-square" alt="Sponsor"/></a>
</p>

Pure bash script that moves Xcode build artifacts, simulator caches and SPM packages to an external USB drive — then creates symlinks so Xcode keeps working transparently. No dependencies, no configuration files, no background processes.

> Your MacBook has 256 GB of SSD. Xcode is eating 50 GB of it with caches you didn't even know existed. You have a 128 GB USB drive sitting in a drawer. This script connects the two.

---

## The Problem

Xcode silently accumulates **30-80 GB** of build artifacts, simulator runtimes and package caches across several hidden directories:

| Directory | What it stores | Typical Size |
|---|---|---|
| `DerivedData` | Build products, indexes, logs | 10-30 GB |
| `iOS DeviceSupport` | Debug symbols for each iOS version | 5-15 GB |
| `CoreSimulator` | Simulator runtimes and data | 5-20 GB |
| `SPM Cache` | Pre-built Swift packages | 1-5 GB |
| `SPM Repos` | Cloned package sources | 1-5 GB |
| `Archives` | Exported .xcarchive bundles | 2-10 GB |

On a 256 GB MacBook, that can be **20-30% of your entire disk** — space you can reclaim instantly if you have an external USB drive with room to spare.

---

## How It Works

```
┌──────────────────────────────────────────────────────────────┐
│  1. SCAN                                                     │
│     Measures disk usage for each Xcode cache directory       │
│     Shows a summary table so you see exactly what's eating   │
│     your SSD before doing anything                           │
└──────────────────────┬───────────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────────┐
│  2. DETECT                                                   │
│     Finds external volumes mounted under /Volumes/           │
│     Filters out system volumes (Macintosh HD, Recovery, etc) │
│     If multiple drives found → interactive picker            │
└──────────────────────┬───────────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────────┐
│  3. SELECT                                                   │
│     Interactive menu — pick individual directories or 'all'  │
│     Shows size and current status (local / already migrated) │
└──────────────────────┬───────────────────────────────────────┘
                       ↓
┌──────────────────────────────────────────────────────────────┐
│  4. MIGRATE                                                  │
│     rsync -a --delete  →  copies data to USB drive           │
│     Verify file count  →  ensures copy is complete           │
│     rm -rf original    →  removes local copy                 │
│     ln -s              →  symlink points to USB copy         │
└──────────────────────────────────────────────────────────────┘

Result: Xcode follows the symlinks natively.
        Your projects build exactly as before.
        Your SSD has 30-80 GB back.
```

The entire process is **reversible** — one command restores everything to the local SSD.

---

## Quick Start

```bash
# Clone
git clone https://github.com/Viniciuscarvalho/mac-ssd-rescue.git
cd mac-ssd-rescue

# Run
./mac-ssd-rescue.sh
```

The interactive wizard walks you through everything:

1. Shows how much space each directory is using
2. Detects your external drive (or lets you pick one)
3. Lets you choose which directories to migrate
4. Moves the data, verifies the copy, creates symlinks

---

## Commands

| Command | What it does |
|---|---|
| `./mac-ssd-rescue.sh` | Interactive migration wizard (default) |
| `./mac-ssd-rescue.sh migrate` | Same as above |
| `./mac-ssd-rescue.sh restore` | Move everything back to local SSD and remove symlinks |
| `./mac-ssd-rescue.sh status` | Show which directories are local vs. migrated |
| `./mac-ssd-rescue.sh usage` | Show current disk usage per directory |

---

## What It Migrates

| Label | Source Path | Safe to move? |
|---|---|---|
| DerivedData | `~/Library/Developer/Xcode/DerivedData` | Yes — Xcode rebuilds on demand |
| iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport` | Yes — re-downloaded when needed |
| CoreSimulator | `~/Library/Developer/CoreSimulator` | Yes — simulators work via symlink |
| SPM Cache | `~/Library/Developer/Xcode/SPMCache` | Yes — re-resolved on next build |
| SPM Repos | `~/Library/Caches/org.swift.swiftpm` | Yes — re-cloned when needed |
| Archives | `~/Library/Developer/Xcode/Archives` | Yes — only needed for re-exports |

All directories are **safe to move** because Xcode follows symlinks transparently and can regenerate any of these caches if the USB drive is disconnected.

---

## Before vs. After

```
BEFORE                              AFTER
─────────────────────────           ─────────────────────────
Macintosh HD (256 GB SSD)           Macintosh HD (256 GB SSD)
├── macOS + Apps    ~80 GB          ├── macOS + Apps    ~80 GB
├── User files      ~50 GB          ├── User files      ~50 GB
├── Xcode caches    ~60 GB ←!       ├── Xcode symlinks  ~0 GB ✓
├── Free space      ~66 GB          ├── Free space     ~126 GB ← +60 GB!
                                    │
                                    USB Drive (128 GB)
                                    └── mac-ssd-rescue/
                                        ├── DerivedData/
                                        ├── iOS DeviceSupport/
                                        ├── CoreSimulator/
                                        └── ...
```

---

## Restoring

Changed your mind? One command brings everything back:

```bash
./mac-ssd-rescue.sh restore
```

This reverses the full process:
1. Copies data from USB back to the original SSD locations
2. Removes the symlinks
3. Recreates the original directories

After restoring, you can safely disconnect the USB drive.

---

## Safety

| Concern | How it's handled |
|---|---|
| Data loss | Every copy is verified (file count comparison) before the original is removed |
| Partial copy | If verification fails, the migration for that directory is aborted — original stays intact |
| Root access | Script refuses to run as root; uses sudo only when strictly needed |
| Wrong drive | System volumes are automatically filtered out; you confirm before any write |
| USB disconnected | Xcode will show build errors, but no data is lost — reconnect and everything works again |

---

## Requirements

- **macOS** Sonoma 14.x, Sequoia 15.x, or macOS 26 (Tahoe)
- **External USB drive** formatted as APFS or Mac OS Extended (HFS+)
- **Zero dependencies** — uses only built-in macOS tools (`rsync`, `ln`, `du`, `df`, `bc`)

---

## Tips

- **Close Xcode and simulators** before migrating for best results
- **Keep the USB drive connected** while using Xcode after migration
- DerivedData is the biggest win — it's fully regenerable and often 10-30 GB alone
- Run `./mac-ssd-rescue.sh status` anytime to check what's local vs. migrated
- The script creates a `mac-ssd-rescue/` folder on the USB drive to keep things organized

---

## Support the Project

If this script saved your MacBook from the "disk almost full" nightmare, consider sponsoring. Your support helps keep it maintained and tested across new macOS versions.

<a href="https://github.com/sponsors/Viniciuscarvalho">
  <img src="https://img.shields.io/badge/Sponsor_mac--ssd--rescue-❤-ea4aaa?style=for-the-badge" alt="Sponsor mac-ssd-rescue"/>
</a>

---

## License

[MIT](https://opensource.org/licenses/MIT)
