# 📦 MiniMyth2 Build Cache System

Sistem otomatis untuk menyimpan dan menggunakan kembali build cache, mempercepat proses build dari **8-9 jam menjadi 1-3 jam**.

## 🚀 Quick Start

### **GitHub Actions (Recommended)**

1. **Build dengan Cache** (Default)
   ```
   GitHub Actions → Build MiniMyth2 Firmware → Run workflow
   - Build Type: full / board_specific
   - Use build cache: ✅ true
   ```

2. **Create Release dengan Cache**
   ```
   - Create release: ✅ true
   ```

### **Manual Usage**

```bash
# Archive cache setelah build
./.github/scripts/archive-build-cache.sh

# Restore cache sebelum build
export GITHUB_REPOSITORY="warpme/minimyth2"
./.github/scripts/restore-build-cache.sh
```

## 📋 Features

- ✅ **Auto-split** large files (>1.9GB) untuk GitHub limit
- ✅ **Checksum verification** untuk data integrity
- ✅ **Smart restore** dengan auto-reassemble
- ✅ **Metadata tracking** (commit, branch, timestamp)
- ✅ **GitHub Release integration**
- ✅ **Exclude firmware** (hanya source code)

## 📊 Performance

| Scenario | Tanpa Cache | Dengan Cache | Saving |
|----------|-------------|--------------|--------|
| First Build | 8-9 jam | 8-9 jam | 0% |
| Rebuild | 8-9 jam | 30-60 min | ~85% |
| Small Changes | 8-9 jam | 1-3 jam | ~70% |
| Board-specific | 3-4 jam | 30-90 min | ~75% |

## 📚 Documentation

- [Build Cache System](./BUILD_CACHE_SYSTEM.md) - Dokumentasi lengkap
- [Build Image for Board](./BUILD_IMAGE_FOR_BOARD.md) - Board-specific builds

## 🔧 Scripts

### **archive-build-cache.sh**
Archive built source code dengan features:
- Scan work directories
- Create exclusion list
- Compress dengan progress
- Auto-split jika >1.9GB
- Generate checksums & manifest

### **restore-build-cache.sh**
Restore cache dari GitHub Release:
- Find latest cache release
- Download all parts
- Verify checksums
- Reassemble split archives
- Extract to project

## 🎯 Workflow Integration

```yaml
# .github/workflows/build-miniarch.yml

inputs:
  use_build_cache:
    description: 'Use build cache from previous release'
    default: true
    type: boolean
  
  create_release:
    description: 'Create release with build cache'
    default: false
    type: boolean
```

## 📦 File Structure

```
.github/
├── scripts/
│   ├── archive-build-cache.sh   # Archive script
│   └── restore-build-cache.sh   # Restore script
└── workflows/
    └── build-miniarch.yml        # Main workflow

build-cache/                      # Archive output
├── minimyth2-build-cache-*.tar.gz
├── *.part-*                      # Split parts (if needed)
├── *.manifest                    # Split manifest
├── *.sha256                      # Checksums
└── metadata.json                 # Build metadata
```

## 🔍 What's Cached

### ✅ Included
- Compiled source code (`work/` directories)
- Build artifacts (`.o`, `.a`, `.so`)
- Downloaded sources
- Build metadata

### ❌ Excluded
- Firmware images (`.img`, `.iso`)
- Final outputs (`.tar.gz`, `.zip`)
- Temporary files
- Log files
- Git directories

## 🆘 Troubleshooting

### Cache tidak ditemukan
```bash
# Check releases
curl -s https://api.github.com/repos/warpme/minimyth2/releases | \
  jq '.[].tag_name' | grep build-cache
```

### Checksum mismatch
```bash
# Verify
sha256sum file.tar.gz
cat file.tar.gz.sha256

# Re-download jika berbeda
```

### Disk space penuh
```bash
# Check space
df -h

# Clean cache
rm -rf build-cache/
rm -rf build-cache-download/
```

## 💡 Best Practices

1. ✅ Create cache after successful full build
2. ✅ Use cache for incremental builds
3. ✅ Update cache after major changes
4. ✅ Keep 3-5 recent cache releases
5. ✅ Monitor disk usage
6. ❌ Don't cache if build failed

## 🔐 GitHub Token

For private repos or API rate limits:

```bash
# Create token: GitHub → Settings → Developer settings → Personal access tokens
# Scopes: repo, workflow

export GITHUB_TOKEN="ghp_xxxxxxxxxxxxx"
```

## 📈 Example Usage

### Scenario 1: CI/CD
```
Build 1: 8-9 hours → Create cache
Build 2: 1-2 hours → Use cache
Build 3+: 30-90 minutes → Use cache
```

### Scenario 2: Development
```bash
# Day 1: Full build + cache
./build-image-for-board.sh 10
./.github/scripts/archive-build-cache.sh

# Day 2: Restore + quick rebuild
./.github/scripts/restore-build-cache.sh
./build-image-for-board.sh 10  # Much faster!
```

### Scenario 3: Team Sharing
```bash
# Developer A: Create & share
- Build + create release
- Share release tag

# Developer B: Use cache
- Restore from release
- Build faster
```

## 🎓 Advanced

### Custom Compression
```bash
# Edit archive-build-cache.sh
COMPRESSION_LEVEL="9"  # Max compression (slower)
COMPRESSION_LEVEL="1"  # Fast compression (larger)
```

### Custom Exclusions
```bash
# Edit create_exclusion_list() in archive-build-cache.sh
*.debug
*.test
custom-dir/
```

## 📞 Support

- [Full Documentation](./BUILD_CACHE_SYSTEM.md)
- [GitHub Issues](https://github.com/warpme/minimyth2/issues)
- [Build Instructions](https://github.com/warpme/minimyth2/wiki/Build-Instructions)

## 📄 License

Same as MiniMyth2 project.

---

**Made with ❤️ for faster MiniMyth2 builds**
