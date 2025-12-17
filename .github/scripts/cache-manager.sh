#!/bin/bash
#
# Build Cache Manager - Interactive CLI
# Easy-to-use interface for managing build cache
#

set -e

VERSION="1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Banner
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║                                                            ║"
    echo "║        MiniMyth2 Build Cache Manager v${VERSION}              ║"
    echo "║                                                            ║"
    echo "║        Manage build cache for faster builds                ║"
    echo "║                                                            ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo ""
}

# Menu
show_menu() {
    echo -e "${BOLD}Main Menu:${NC}"
    echo ""
    echo -e "  ${GREEN}1)${NC} Create Build Cache Archive"
    echo -e "  ${GREEN}2)${NC} Restore Build Cache from Release"
    echo -e "  ${GREEN}3)${NC} Check Cache Status"
    echo -e "  ${GREEN}4)${NC} List Available Cache Releases"
    echo -e "  ${GREEN}5)${NC} Clean Local Cache"
    echo -e "  ${GREEN}6)${NC} Show Cache Statistics"
    echo -e "  ${GREEN}7)${NC} Help & Documentation"
    echo -e "  ${RED}0)${NC} Exit"
    echo ""
}

# Check cache status
check_cache_status() {
    echo -e "${BLUE}[INFO]${NC} Checking cache status..."
    echo ""
    
    local project_root="$(cd "$SCRIPT_DIR/../.." && pwd)"
    local has_cache=false
    
    # Check work directories
    local work_dirs=(
        "$project_root/script/meta/minimyth/work"
        "$project_root/script/meta/miniarch/work"
        "$project_root/script/bootloaders/work"
    )
    
    echo -e "${BOLD}Local Cache Status:${NC}"
    for dir in "${work_dirs[@]}"; do
        if [ -d "$dir" ] && [ "$(ls -A "$dir" 2>/dev/null)" ]; then
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            echo -e "  ✅ ${dir#$project_root/} - ${GREEN}${size}${NC}"
            has_cache=true
        else
            echo -e "  ❌ ${dir#$project_root/} - ${RED}Empty${NC}"
        fi
    done
    
    echo ""
    
    if [ "$has_cache" = true ]; then
        echo -e "${GREEN}[SUCCESS]${NC} Build cache found locally"
    else
        echo -e "${YELLOW}[WARNING]${NC} No build cache found"
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

# List available releases
list_releases() {
    echo -e "${BLUE}[INFO]${NC} Fetching available cache releases..."
    echo ""
    
    local repo="${GITHUB_REPOSITORY:-warpme/minimyth2}"
    local api_url="https://api.github.com/repos/${repo}/releases"
    
    # Fetch releases
    local releases=$(curl -s "$api_url" | jq -r '.[] | select(.tag_name | contains("build-cache")) | "\(.tag_name)|\(.created_at)|\(.body)"' | head -n 10)
    
    if [ -z "$releases" ]; then
        echo -e "${YELLOW}[WARNING]${NC} No cache releases found"
        echo ""
        read -p "Press Enter to continue..."
        return
    fi
    
    echo -e "${BOLD}Available Cache Releases:${NC}"
    echo ""
    
    local count=1
    while IFS='|' read -r tag date body; do
        echo -e "${GREEN}${count})${NC} ${BOLD}${tag}${NC}"
        echo -e "   Date: ${date}"
        echo -e "   Info: $(echo "$body" | head -n 1)"
        echo ""
        count=$((count + 1))
    done <<< "$releases"
    
    read -p "Press Enter to continue..."
}

# Clean local cache
clean_cache() {
    echo -e "${YELLOW}[WARNING]${NC} This will delete all local build cache!"
    echo ""
    read -p "Are you sure? (yes/no): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo -e "${BLUE}[INFO]${NC} Cancelled"
        sleep 1
        return
    fi
    
    echo ""
    echo -e "${BLUE}[INFO]${NC} Cleaning cache..."
    
    local project_root="$(cd "$SCRIPT_DIR/../.." && pwd)"
    
    # Remove work directories
    find "$project_root" -type d -name "work" -exec rm -rf {} + 2>/dev/null || true
    
    # Remove cache directories
    rm -rf "$project_root/build-cache" 2>/dev/null || true
    rm -rf "$project_root/build-cache-download" 2>/dev/null || true
    
    echo -e "${GREEN}[SUCCESS]${NC} Cache cleaned"
    echo ""
    read -p "Press Enter to continue..."
}

# Show statistics
show_statistics() {
    echo -e "${BLUE}[INFO]${NC} Calculating cache statistics..."
    echo ""
    
    local project_root="$(cd "$SCRIPT_DIR/../.." && pwd)"
    
    echo -e "${BOLD}Cache Statistics:${NC}"
    echo ""
    
    # Total work directory size
    local total_size=$(find "$project_root" -type d -name "work" -exec du -sb {} + 2>/dev/null | awk '{sum+=$1} END {print sum}')
    if [ -n "$total_size" ] && [ "$total_size" -gt 0 ]; then
        local size_gb=$(echo "scale=2; $total_size / 1024 / 1024 / 1024" | bc)
        echo -e "  Total Cache Size: ${GREEN}${size_gb} GB${NC}"
    else
        echo -e "  Total Cache Size: ${RED}0 GB${NC}"
    fi
    
    # Count work directories
    local work_count=$(find "$project_root" -type d -name "work" 2>/dev/null | wc -l)
    echo -e "  Work Directories: ${GREEN}${work_count}${NC}"
    
    # Archive size if exists
    if [ -d "$project_root/build-cache" ]; then
        local archive_size=$(du -sh "$project_root/build-cache" 2>/dev/null | cut -f1)
        echo -e "  Archive Size: ${GREEN}${archive_size}${NC}"
    fi
    
    echo ""
    
    # Disk usage
    echo -e "${BOLD}Disk Usage:${NC}"
    df -h "$project_root" | tail -n 1 | awk '{print "  Total: "$2"  Used: "$3"  Available: "$4"  Use%: "$5}'
    
    echo ""
    read -p "Press Enter to continue..."
}

# Show help
show_help() {
    echo -e "${BOLD}Build Cache Manager - Help${NC}"
    echo ""
    echo -e "${CYAN}What is Build Cache?${NC}"
    echo "  Build cache stores compiled source code to speed up subsequent builds."
    echo "  First build: 8-9 hours → With cache: 1-3 hours"
    echo ""
    echo -e "${CYAN}How it works:${NC}"
    echo "  1. Build firmware normally"
    echo "  2. Create cache archive (excludes firmware images)"
    echo "  3. Upload to GitHub Release"
    echo "  4. Future builds restore cache first"
    echo "  5. Build completes much faster"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo "  Create Archive  - Archive current build cache"
    echo "  Restore Cache   - Download and restore from release"
    echo "  Check Status    - View local cache status"
    echo "  List Releases   - Show available cache releases"
    echo "  Clean Cache     - Remove local cache"
    echo "  Statistics      - Show cache size and disk usage"
    echo ""
    echo -e "${CYAN}Environment Variables:${NC}"
    echo "  GITHUB_REPOSITORY - Repository name (default: warpme/minimyth2)"
    echo "  GITHUB_TOKEN      - GitHub token for private repos"
    echo ""
    echo -e "${CYAN}Documentation:${NC}"
    echo "  Full docs: docs/BUILD_CACHE_SYSTEM.md"
    echo "  Quick ref: .github/scripts/README.md"
    echo ""
    read -p "Press Enter to continue..."
}

# Main loop
main() {
    while true; do
        show_banner
        show_menu
        
        read -p "Select option [0-7]: " choice
        echo ""
        
        case $choice in
            1)
                echo -e "${BLUE}[INFO]${NC} Running archive script..."
                echo ""
                "$SCRIPT_DIR/archive-build-cache.sh"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            2)
                echo -e "${BLUE}[INFO]${NC} Running restore script..."
                echo ""
                "$SCRIPT_DIR/restore-build-cache.sh"
                echo ""
                read -p "Press Enter to continue..."
                ;;
            3)
                check_cache_status
                ;;
            4)
                list_releases
                ;;
            5)
                clean_cache
                ;;
            6)
                show_statistics
                ;;
            7)
                show_help
                ;;
            0)
                echo -e "${GREEN}[INFO]${NC} Goodbye!"
                exit 0
                ;;
            *)
                echo -e "${RED}[ERROR]${NC} Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Run main
main
