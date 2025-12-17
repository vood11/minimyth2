#!/bin/bash
#
# Archive Build Cache Script
# Purpose: Archive built source code (excluding firmware images) for reuse
# This significantly speeds up subsequent builds by caching compiled sources
#

set -e

VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Configuration
CACHE_DIR="${PROJECT_ROOT}/build-cache"
ARCHIVE_PREFIX="minimyth2-build-cache"
MAX_PART_SIZE="1900M"  # GitHub release limit is 2GB, use 1.9GB to be safe
COMPRESSION_LEVEL="6"   # Balance between speed and size (1-9)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to get build metadata
get_build_metadata() {
    local metadata_file="${CACHE_DIR}/metadata.json"
    
    cat > "$metadata_file" <<EOF
{
  "version": "${VERSION}",
  "created_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "git_commit": "$(git -C "$PROJECT_ROOT" rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "git_branch": "$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')",
  "architecture": "${ARCH:-aarch64}",
  "hostname": "$(hostname)",
  "build_user": "$(whoami)"
}
EOF
    
    log_info "Build metadata created"
}

# Function to find directories to archive
find_build_directories() {
    log_info "Scanning for build directories..."
    
    local dirs_to_archive=(
        "script/meta/minimyth/work"
        "script/meta/miniarch/work"
        "script/bootloaders/work"
        "script/kernel/work"
        "script/lib/work"
        "script/utils/work"
        "script/X11/work"
        "script/myth*/work"
        "script/opengl/work"
        "script/python*/work"
        "script/devel/work"
    )
    
    local found_dirs=()
    
    for pattern in "${dirs_to_archive[@]}"; do
        while IFS= read -r -d '' dir; do
            if [ -d "$dir" ]; then
                found_dirs+=("$dir")
                log_info "  Found: ${dir#$PROJECT_ROOT/}"
            fi
        done < <(find "$PROJECT_ROOT" -path "*/$pattern" -type d -print0 2>/dev/null || true)
    done
    
    echo "${found_dirs[@]}"
}

# Function to create exclusion list
create_exclusion_list() {
    local exclude_file="${CACHE_DIR}/exclude.txt"
    
    cat > "$exclude_file" <<'EOF'
# Exclude firmware images and final build outputs
*.img
*.img.gz
*.img.xz
*.img.bz2
*.iso
*.tar.gz
*.tar.bz2
*.tar.xz
*.zip

# Exclude images directory
images/
main/
boot/

# Exclude temporary files
*.tmp
*.temp
*~
.*.swp

# Exclude logs (keep them separate)
*.log
log/

# Exclude git directories
.git/
.gitignore

# Exclude download cache (can be re-downloaded)
download/

# Exclude cookies and stamps that force rebuilds
cookies/
stamps/

# Keep compiled objects and sources
# *.o
# *.a
# *.so*
EOF
    
    log_info "Exclusion list created"
    echo "$exclude_file"
}

# Function to estimate archive size
estimate_size() {
    local dirs=("$@")
    local total_size=0
    
    log_info "Estimating archive size..."
    
    for dir in "${dirs[@]}"; do
        if [ -d "$dir" ]; then
            local size=$(du -sb "$dir" 2>/dev/null | cut -f1 || echo "0")
            total_size=$((total_size + size))
        fi
    done
    
    local size_gb=$(echo "scale=2; $total_size / 1024 / 1024 / 1024" | bc)
    log_info "Estimated size: ${size_gb} GB (before compression)"
    
    echo "$total_size"
}

# Function to create archive with progress
create_archive() {
    local archive_name="$1"
    shift
    local dirs=("$@")
    local exclude_file="${CACHE_DIR}/exclude.txt"
    
    log_info "Creating archive: ${archive_name}"
    log_info "This may take a while..."
    
    # Create tar archive with compression and progress
    tar -czf "$archive_name" \
        --exclude-from="$exclude_file" \
        -C "$PROJECT_ROOT" \
        --checkpoint=10000 \
        --checkpoint-action=dot \
        "${dirs[@]/#$PROJECT_ROOT\//}" 2>&1 | \
        while IFS= read -r line; do
            echo -n "."
        done
    
    echo ""
    
    if [ -f "$archive_name" ]; then
        local size=$(du -h "$archive_name" | cut -f1)
        log_success "Archive created: ${archive_name} (${size})"
        return 0
    else
        log_error "Failed to create archive"
        return 1
    fi
}

# Function to split archive if needed
split_archive() {
    local archive_file="$1"
    local archive_size=$(stat -f%z "$archive_file" 2>/dev/null || stat -c%s "$archive_file" 2>/dev/null)
    local max_size=$(numfmt --from=iec "$MAX_PART_SIZE")
    
    if [ "$archive_size" -gt "$max_size" ]; then
        log_warning "Archive size ($(numfmt --to=iec $archive_size)) exceeds GitHub limit"
        log_info "Splitting archive into parts..."
        
        # Split the archive
        split -b "$MAX_PART_SIZE" -d "$archive_file" "${archive_file}.part-"
        
        # Create checksum file
        local checksum_file="${archive_file}.sha256"
        sha256sum "$archive_file" > "$checksum_file"
        
        # Count parts
        local part_count=$(ls -1 "${archive_file}.part-"* 2>/dev/null | wc -l)
        log_success "Archive split into ${part_count} parts"
        
        # Create manifest
        local manifest_file="${archive_file}.manifest"
        cat > "$manifest_file" <<EOF
{
  "original_file": "$(basename "$archive_file")",
  "original_size": $archive_size,
  "part_size": "$MAX_PART_SIZE",
  "part_count": $part_count,
  "checksum": "$(cat "$checksum_file" | cut -d' ' -f1)",
  "parts": [
$(ls -1 "${archive_file}.part-"* | while read part; do
    echo "    \"$(basename "$part")\""
done | paste -sd, -)
  ]
}
EOF
        
        log_info "Manifest created: ${manifest_file}"
        
        # Remove original archive to save space
        rm -f "$archive_file"
        
        return 0
    else
        log_success "Archive size is within GitHub limits, no splitting needed"
        
        # Still create checksum
        sha256sum "$archive_file" > "${archive_file}.sha256"
        
        return 1
    fi
}

# Function to create archive list file
create_archive_list() {
    local output_dir="$1"
    local list_file="${output_dir}/archive-files.txt"
    
    log_info "Creating file list for upload..."
    
    find "$output_dir" -type f \( \
        -name "*.tar.gz" -o \
        -name "*.part-*" -o \
        -name "*.sha256" -o \
        -name "*.manifest" -o \
        -name "metadata.json" \
    \) > "$list_file"
    
    local file_count=$(wc -l < "$list_file")
    log_success "Found ${file_count} files to upload"
    
    echo "$list_file"
}

# Main archive function
main_archive() {
    log_info "=== MiniMyth2 Build Cache Archiver v${VERSION} ==="
    
    # Create cache directory
    mkdir -p "$CACHE_DIR"
    
    # Get build metadata
    get_build_metadata
    
    # Create exclusion list
    create_exclusion_list
    
    # Find directories to archive
    local dirs=($(find_build_directories))
    
    if [ ${#dirs[@]} -eq 0 ]; then
        log_warning "No build directories found to archive"
        exit 0
    fi
    
    log_info "Found ${#dirs[@]} directories to archive"
    
    # Estimate size
    estimate_size "${dirs[@]}"
    
    # Create timestamp for archive name
    local timestamp=$(date +"%Y%m%d-%H%M%S")
    local git_hash=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    local archive_name="${CACHE_DIR}/${ARCHIVE_PREFIX}-${timestamp}-${git_hash}.tar.gz"
    
    # Create archive
    if create_archive "$archive_name" "${dirs[@]}"; then
        # Split if needed
        split_archive "$archive_name"
        
        # Create file list
        create_archive_list "$CACHE_DIR"
        
        log_success "=== Archive process completed ==="
        log_info "Cache directory: ${CACHE_DIR}"
        log_info "Files ready for upload to GitHub Release"
        
        # Output summary
        echo ""
        echo "=== Upload Summary ==="
        ls -lh "$CACHE_DIR"
        
        exit 0
    else
        log_error "Archive creation failed"
        exit 1
    fi
}

# Run main function
main_archive
