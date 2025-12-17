#!/bin/bash
#
# Restore Build Cache Script
# Purpose: Download and restore build cache from GitHub Release
# This speeds up builds by reusing previously compiled sources
#

set -e

VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Configuration
CACHE_DIR="${PROJECT_ROOT}/build-cache-download"
GITHUB_REPO="${GITHUB_REPOSITORY:-warpme/minimyth2}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

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

# Function to find latest release with build cache
find_latest_cache_release() {
    log_info "Searching for latest build cache release..."
    
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases"
    local auth_header=""
    
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="Authorization: token ${GITHUB_TOKEN}"
    fi
    
    # Get releases and find one with build cache
    local release_data
    if [ -n "$auth_header" ]; then
        release_data=$(curl -s -H "$auth_header" "$api_url")
    else
        release_data=$(curl -s "$api_url")
    fi
    
    # Find release with build cache assets
    local release_tag=$(echo "$release_data" | jq -r '.[] | select(.assets[].name | contains("build-cache")) | .tag_name' | head -n1)
    
    if [ -n "$release_tag" ] && [ "$release_tag" != "null" ]; then
        log_success "Found build cache in release: ${release_tag}"
        echo "$release_tag"
        return 0
    else
        log_warning "No build cache found in recent releases"
        return 1
    fi
}

# Function to download release assets
download_cache_assets() {
    local release_tag="$1"
    
    log_info "Downloading build cache from release: ${release_tag}"
    
    mkdir -p "$CACHE_DIR"
    
    local api_url="https://api.github.com/repos/${GITHUB_REPO}/releases/tags/${release_tag}"
    local auth_header=""
    
    if [ -n "$GITHUB_TOKEN" ]; then
        auth_header="Authorization: token ${GITHUB_TOKEN}"
    fi
    
    # Get release data
    local release_data
    if [ -n "$auth_header" ]; then
        release_data=$(curl -s -H "$auth_header" "$api_url")
    else
        release_data=$(curl -s "$api_url")
    fi
    
    # Download all build cache related files
    echo "$release_data" | jq -r '.assets[] | select(.name | contains("build-cache")) | .browser_download_url' | while read url; do
        local filename=$(basename "$url")
        log_info "Downloading: ${filename}"
        
        if [ -n "$auth_header" ]; then
            curl -L -H "$auth_header" -o "${CACHE_DIR}/${filename}" "$url"
        else
            curl -L -o "${CACHE_DIR}/${filename}" "$url"
        fi
        
        if [ $? -eq 0 ]; then
            log_success "Downloaded: ${filename}"
        else
            log_error "Failed to download: ${filename}"
            return 1
        fi
    done
    
    return 0
}

# Function to verify checksums
verify_checksums() {
    log_info "Verifying checksums..."
    
    local checksum_file=$(find "$CACHE_DIR" -name "*.sha256" | head -n1)
    
    if [ -z "$checksum_file" ]; then
        log_warning "No checksum file found, skipping verification"
        return 0
    fi
    
    cd "$CACHE_DIR"
    
    if sha256sum -c "$checksum_file" 2>/dev/null; then
        log_success "Checksum verification passed"
        return 0
    else
        log_error "Checksum verification failed"
        return 1
    fi
}

# Function to reassemble split archives
reassemble_archive() {
    log_info "Checking for split archives..."
    
    local manifest_file=$(find "$CACHE_DIR" -name "*.manifest" | head -n1)
    
    if [ -z "$manifest_file" ]; then
        log_info "No split archive found, looking for complete archive..."
        local archive_file=$(find "$CACHE_DIR" -name "*.tar.gz" -not -name "*.part-*" | head -n1)
        
        if [ -n "$archive_file" ]; then
            log_success "Found complete archive: $(basename "$archive_file")"
            echo "$archive_file"
            return 0
        else
            log_error "No archive found"
            return 1
        fi
    fi
    
    log_info "Found split archive manifest"
    
    # Read manifest
    local original_file=$(jq -r '.original_file' "$manifest_file")
    local part_count=$(jq -r '.part_count' "$manifest_file")
    
    log_info "Reassembling ${part_count} parts into ${original_file}..."
    
    # Reassemble parts
    local output_file="${CACHE_DIR}/${original_file}"
    cat "${CACHE_DIR}"/*.part-* > "$output_file"
    
    if [ -f "$output_file" ]; then
        log_success "Archive reassembled: ${original_file}"
        
        # Verify checksum if available
        local expected_checksum=$(jq -r '.checksum' "$manifest_file")
        local actual_checksum=$(sha256sum "$output_file" | cut -d' ' -f1)
        
        if [ "$expected_checksum" = "$actual_checksum" ]; then
            log_success "Checksum verification passed"
        else
            log_error "Checksum mismatch!"
            log_error "Expected: ${expected_checksum}"
            log_error "Actual:   ${actual_checksum}"
            return 1
        fi
        
        echo "$output_file"
        return 0
    else
        log_error "Failed to reassemble archive"
        return 1
    fi
}

# Function to extract archive
extract_archive() {
    local archive_file="$1"
    
    log_info "Extracting archive to project root..."
    log_info "This may take a while..."
    
    # Extract with progress
    tar -xzf "$archive_file" \
        -C "$PROJECT_ROOT" \
        --checkpoint=10000 \
        --checkpoint-action=dot 2>&1 | \
        while IFS= read -r line; do
            echo -n "."
        done
    
    echo ""
    
    if [ $? -eq 0 ]; then
        log_success "Archive extracted successfully"
        return 0
    else
        log_error "Failed to extract archive"
        return 1
    fi
}

# Function to check if cache exists locally
check_existing_cache() {
    log_info "Checking for existing build cache..."
    
    local work_dirs=(
        "${PROJECT_ROOT}/script/meta/minimyth/work"
        "${PROJECT_ROOT}/script/meta/miniarch/work"
    )
    
    for dir in "${work_dirs[@]}"; do
        if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
            log_warning "Existing build cache found at: ${dir}"
            return 0
        fi
    done
    
    log_info "No existing build cache found"
    return 1
}

# Main restore function
main_restore() {
    log_info "=== MiniMyth2 Build Cache Restorer v${VERSION} ==="
    
    # Check for existing cache
    if check_existing_cache; then
        echo ""
        read -p "Existing cache found. Overwrite? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Restore cancelled by user"
            exit 0
        fi
    fi
    
    # Find latest release with cache
    local release_tag
    if ! release_tag=$(find_latest_cache_release); then
        log_error "No build cache available"
        exit 1
    fi
    
    # Download cache assets
    if ! download_cache_assets "$release_tag"; then
        log_error "Failed to download cache assets"
        exit 1
    fi
    
    # Reassemble archive if split
    local archive_file
    if ! archive_file=$(reassemble_archive); then
        log_error "Failed to prepare archive"
        exit 1
    fi
    
    # Extract archive
    if ! extract_archive "$archive_file"; then
        log_error "Failed to extract archive"
        exit 1
    fi
    
    # Cleanup
    log_info "Cleaning up temporary files..."
    rm -rf "$CACHE_DIR"
    
    log_success "=== Build cache restored successfully ==="
    log_info "You can now run the build process"
    log_info "The build will use cached sources and should be much faster"
    
    exit 0
}

# Run main function
main_restore
