# mac-ssd-rescue

Reclaim SSD space on a Mac by migrating Xcode build artifacts, simulator caches and SPM packages to an external USB drive.

Works on **macOS Sonoma**, **Sequoia** and **macOS 26 (Tahoe)**.
No dependencies — pure bash + built-in macOS tools.

## The Problem

Xcode can easily consume **30-80 GB** of your SSD with:

| Directory | Typical Size |
|---|---|
| `DerivedData` | 10-30 GB |
| `iOS DeviceSupport` | 5-15 GB |
| `CoreSimulator` | 5-20 GB |
| `SPM Cache / Repos` | 2-10 GB |
| `Archives` | 2-10 GB |

If you have an external USB drive with plenty of space, this script moves those artifacts there and creates symlinks so Xcode keeps working transparently.

## Quick Start

```bash
# Clone
git clone https://github.com/Viniciuscarvalho/mac-ssd-rescue.git
cd mac-ssd-rescue

# Run
./mac-ssd-rescue.sh
```

The interactive wizard will:
1. Show how much space each directory is using
2. Detect your external drive (or let you pick one)
3. Let you choose which directories to migrate
4. Move the data and create symlinks

## Commands

```bash
./mac-ssd-rescue.sh migrate   # Move artifacts to USB (default)
./mac-ssd-rescue.sh restore   # Move everything back to SSD
./mac-ssd-rescue.sh status    # Show what's local vs. migrated
./mac-ssd-rescue.sh usage     # Show disk usage per directory
```

## What It Migrates

| Label | Source Path |
|---|---|
| DerivedData | `~/Library/Developer/Xcode/DerivedData` |
| iOS DeviceSupport | `~/Library/Developer/Xcode/iOS DeviceSupport` |
| CoreSimulator | `~/Library/Developer/CoreSimulator` |
| SPM Cache | `~/Library/Developer/Xcode/SPMCache` |
| SPM Repos | `~/Library/Caches/org.swift.swiftpm` |
| Archives | `~/Library/Developer/Xcode/Archives` |

## How It Works

1. **Copies** the selected directory to the USB drive using `rsync`
2. **Verifies** the copy by comparing file counts
3. **Replaces** the original directory with a symlink pointing to the USB copy

Xcode follows symlinks natively, so everything keeps working as before.

## Restoring

If you want to move everything back to the local SSD:

```bash
./mac-ssd-rescue.sh restore
```

This reverses the process: copies data back from USB, removes symlinks, and recreates the original directories.

## Requirements

- macOS Sonoma 14.x, Sequoia 15.x, or macOS 26 (Tahoe)
- An external USB drive formatted as APFS or Mac OS Extended (HFS+)
- No additional dependencies — uses only built-in macOS tools (`rsync`, `ln`, `du`, `df`)

## Important Notes

- **Keep the USB drive connected** while using Xcode after migration
- The script will **not** run as root — it uses `sudo` only when absolutely needed
- Before migrating, close Xcode and any running simulators for best results
- The script verifies each copy before removing the original

## License

MIT License. See [LICENSE](LICENSE) for details.
