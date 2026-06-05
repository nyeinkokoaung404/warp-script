#!/data/data/com.termux/files/usr/bin/bash

## ---------------------------
## WARP IP Finder for Termux v1.0
## Find optimal Cloudflare WARP endpoints
## ---------------------------

# Color definitions for Termux
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Default settings
THREADS=${THREADS:-10}
TIMEOUT=${TIMEOUT:-3}
OUTPUT_FILE="warp_endpoints.txt"
RESULTS_FILE="warp_results.txt"
CONFIG_FILE="warp_config.txt"
DEFAULT_PORTS=("2408" "500" "1701" "4500")

# WARP IP ranges (Cloudflare's IP ranges)
WARP_IPV4_RANGES=(
    "162.159.192.0/24"
    "162.159.193.0/24"
    "162.159.195.0/24"
    "188.114.96.0/24"
    "188.114.97.0/24"
    "188.114.98.0/24"
    "188.114.99.0/24"
)

# Function to print colored output
print_header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}         $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}➜ $1${NC}"
}

print_warning() {
    echo -e "${BLUE}⚠ $1${NC}"
}

# Check and install dependencies for Termux
check_dependencies() {
    print_info "Checking dependencies for Termux..."
    
    local missing=()
    local to_install=()
    
    # Check for required commands
    for cmd in curl ping bc sort awk; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    # Check for netcat (nc) - Termux might not have it
    if ! command -v nc &> /dev/null; then
        missing+=("netcat")
        to_install+=("netcat-openbsd")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_warning "Missing dependencies: ${missing[*]}"
        print_info "Installing packages for Termux..."
        
        # Update Termux packages
        pkg update -y 2>/dev/null
        
        # Install required packages
        for pkg in bc curl netcat-openbsd; do
            if ! command -v $pkg &> /dev/null && [[ $pkg != "netcat-openbsd" ]]; then
                pkg install -y $pkg 2>/dev/null
            elif [[ $pkg == "netcat-openbsd" ]]; then
                pkg install -y netcat-openbsd 2>/dev/null
            fi
        done
        
        print_success "Dependencies installed"
    else
        print_success "All dependencies satisfied"
    fi
    
    # Check if running in Termux
    if [[ ! -d "/data/data/com.termux" ]]; then
        print_warning "Not running in Termux. Some features may not work properly."
    else
        print_success "Termux environment detected"
        # Request storage permission if needed
        if [[ ! -d "$HOME/storage" ]]; then
            print_info "Run 'termux-setup-storage' to access storage if needed"
        fi
    fi
}

# Simple ping test (Termux compatible)
ping_test() {
    local ip=$1
    local count=${2:-2}
    
    if command -v ping &> /dev/null; then
        ping -c $count -W 2 $ip 2>/dev/null | grep -oP 'time=\K[0-9.]+' | head -1
    else
        echo ""
    fi
}

# Test a single endpoint (Termux optimized)
test_endpoint() {
    local ip=$1
    local port=$2
    
    local start_time=$(date +%s%N)
    
    # Try TCP connection first (more reliable in Termux)
    timeout $TIMEOUT bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null
    local tcp_result=$?
    
    if [[ $tcp_result -eq 0 ]]; then
        local end_time=$(date +%s%N)
        local latency=$(( (end_time - start_time) / 1000000 ))
        echo "$ip:$port|$latency|SUCCESS"
    else
        # Try UDP with nc if TCP fails
        if command -v nc &> /dev/null; then
            timeout $TIMEOUT bash -c "echo test | nc -u -w1 $ip $port" 2>/dev/null
            local udp_result=$?
            local end_time=$(date +%s%N)
            local latency=$(( (end_time - start_time) / 1000000 ))
            
            if [[ $udp_result -eq 0 ]]; then
                echo "$ip:$port|$latency|SUCCESS"
            else
                echo "$ip:$port|$latency|FAILED"
            fi
        else
            echo "$ip:$port|0|FAILED"
        fi
    fi
}

# Scan endpoints with limited parallelism for Termux
scan_endpoints() {
    local ips=("$@")
    local total=${#ips[@]}
    local completed=0
    local results=()
    
    # Use fewer threads for Termux to avoid overload
    local max_threads=$THREADS
    if [[ $max_threads -gt 20 ]]; then
        max_threads=20
        print_warning "Reducing threads to $max_threads for Termux compatibility"
    fi
    
    print_info "Scanning $total endpoints with $max_threads threads..."
    
    # Create temp directory
    local temp_dir=$(mktemp -d)
    
    # Process in smaller batches for Termux
    local batch_size=$max_threads
    
    for ((i=0; i<total; i+=batch_size)); do
        local batch=()
        for ((j=i; j<i+batch_size && j<total; j++)); do
            batch+=("${ips[$j]}")
        done
        
        # Test batch
        for endpoint in "${batch[@]}"; do
            (
                local ip=$(echo $endpoint | cut -d: -f1)
                local port=$(echo $endpoint | cut -d: -f2)
                local result=$(test_endpoint $ip $port)
                echo "$result" > "$temp_dir/result_$$_$RANDOM.txt"
            ) &
            
            # Small delay to prevent overwhelming Termux
            sleep 0.1
        done
        
        wait
        
        # Collect results
        for result_file in "$temp_dir"/result_*; do
            if [[ -f "$result_file" ]]; then
                local result=$(cat "$result_file")
                results+=("$result")
                ((completed++))
                
                # Show progress every 10 endpoints
                if (( completed % 10 == 0 )); then
                    echo -ne "\r${YELLOW}Progress: $completed/$total ($((completed * 100 / total))%)${NC}    "
                fi
                rm -f "$result_file"
            fi
        done
    done
    
    echo ""
    rm -rf "$temp_dir"
    
    # Filter and sort results
    local successful=()
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" =~ SUCCESS ]]; then
            successful+=("$line")
        fi
    done <<< "$(printf "%s\n" "${results[@]}")"
    
    # Sort by latency
    printf "%s\n" "${successful[@]}" | sort -t'|' -k2 -n
}

# Generate IP list from ranges (simplified for Termux)
generate_ip_list() {
    local ips=()
    
    print_info "Generating IP addresses..."
    
    # Use fewer IPs for Termux to save time
    for range in "${WARP_IPV4_RANGES[@]}"; do
        # Parse CIDR
        local ip=$(echo $range | cut -d/ -f1)
        local prefix=$(echo $range | cut -d/ -f2)
        
        # Only generate first 10 IPs per range for Termux
        local IFS=.
        read -r a b c d <<< "$ip"
        
        for k in {1..10}; do
            local last_octet=$((RANDOM % 254 + 1))
            local gen_ip="$a.$b.$c.$last_octet"
            for port in "${DEFAULT_PORTS[@]}"; do
                ips+=("$gen_ip:$port")
            done
        done
    done
    
    echo "${ips[@]}"
}

# Quick scan mode (Termux optimized)
quick_scan() {
    print_header "Quick WARP Endpoint Scan (Termux)"
    
    # Common working endpoints
    local known_endpoints=(
        "162.159.192.1:2408"
        "162.159.193.1:2408"
        "162.159.195.1:2408"
        "188.114.96.1:2408"
        "188.114.97.1:2408"
        "188.114.98.1:2408"
        "188.114.99.1:2408"
    )
    
    print_info "Testing known endpoints..."
    echo ""
    
    local results=()
    for endpoint in "${known_endpoints[@]}"; do
        printf "  Testing %-20s ... " "$endpoint"
        local ip=$(echo $endpoint | cut -d: -f1)
        local port=$(echo $endpoint | cut -d: -f2)
        local result=$(test_endpoint $ip $port)
        local status=$(echo $result | cut -d'|' -f3)
        local latency=$(echo $result | cut -d'|' -f2)
        
        if [[ $status == "SUCCESS" ]]; then
            echo -e "${GREEN}OK${NC} (${latency}ms)"
            results+=("$result")
        else
            echo -e "${RED}FAILED${NC}"
        fi
        sleep 0.2  # Small delay for Termux
    done
    
    echo ""
    save_results "${results[@]}"
}

# Full scan mode (Termux optimized)
full_scan() {
    print_header "Full WARP Endpoint Scan (Termux)"
    
    print_warning "Full scan may take several minutes on Termux"
    read -p "Continue? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Scan cancelled"
        return
    fi
    
    local ips=($(generate_ip_list))
    
    print_info "Total endpoints to test: ${#ips[@]}"
    
    # Start scan
    local results=$(scan_endpoints "${ips[@]}")
    
    # Filter successful results
    local successful=()
    while IFS= read -r line; do
        if [[ -n "$line" && "$line" =~ SUCCESS ]]; then
            successful+=("$line")
        fi
    done <<< "$results"
    
    # Save results
    save_results "${successful[@]}"
}

# Save results to file
save_results() {
    local results=("$@")
    
    if [[ ${#results[@]} -eq 0 ]]; then
        print_error "No successful endpoints found"
        print_info "Try using Quick Scan or check your internet connection"
        return 1
    fi
    
    # Sort by latency
    IFS=$'\n' sorted=($(sort -t'|' -k2 -n <<<"${results[*]}"))
    unset IFS
    
    # Save to files
    echo "# WARP Endpoints - $(date)" > "$OUTPUT_FILE"
    echo "# Format: IP:PORT" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    > "$RESULTS_FILE"
    
    for result in "${sorted[@]}"; do
        local endpoint=$(echo $result | cut -d'|' -f1)
        local latency=$(echo $result | cut -d'|' -f2)
        
        echo "$endpoint" >> "$OUTPUT_FILE"
        echo "$result" >> "$RESULTS_FILE"
    done
    
    print_success "Results saved to:"
    echo -e "  ${GREEN}$OUTPUT_FILE${NC} - IP:PORT list"
    echo -e "  ${GREEN}$RESULTS_FILE${NC} - Full details"
    
    # Display top results
    echo ""
    print_header "Top 5 WARP Endpoints"
    local rank=1
    for result in "${sorted[@]:0:5}"; do
        local endpoint=$(echo $result | cut -d'|' -f1)
        local latency=$(echo $result | cut -d'|' -f2)
        echo -e "  ${GREEN}#$rank${NC} $endpoint - ${GREEN}${latency}ms${NC}"
        ((rank++))
    done
}

# Generate config for various WARP clients
generate_config() {
    print_header "Generate WARP Configuration"
    
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        print_error "No endpoints found. Run scan first."
        return 1
    fi
    
    local best_endpoint=$(grep -v '^#' "$OUTPUT_FILE" | grep -v '^$' | head -n 1)
    
    if [[ -z "$best_endpoint" ]]; then
        print_error "No valid endpoints found"
        return 1
    fi
    
    echo ""
    print_info "Best endpoint: ${GREEN}$best_endpoint${NC}"
    echo ""
    
    # Save to config file
    cat > "$CONFIG_FILE" << EOF
==========================================
WARP CONFIGURATION - Generated $(date)
==========================================

Best Endpoint: $best_endpoint

------------------------------------------
For WARP-Cli (Cloudflare official client)
------------------------------------------
warp-cli set-custom-endpoint $best_endpoint

------------------------------------------
For WARP-GO (/opt/warp-go/warp.conf)
------------------------------------------
Endpoint = $best_endpoint

------------------------------------------
For WGCF (/etc/wireguard/wgcf.conf)
------------------------------------------
Endpoint = $best_endpoint

------------------------------------------
For WireProxy (/etc/wireguard/proxy.conf)
------------------------------------------
Endpoint = $best_endpoint

==========================================
EOF

    # Display config
    cat "$CONFIG_FILE"
    
    print_success "Configuration saved to $CONFIG_FILE"
}

# Show current status
show_status() {
    print_header "Current Status"
    
    if [[ -f "$OUTPUT_FILE" ]]; then
        local endpoint_count=$(grep -v '^#' "$OUTPUT_FILE" | grep -v '^$' | wc -l)
        echo -e "  Endpoints found: ${GREEN}$endpoint_count${NC}"
        
        local best=$(grep -v '^#' "$OUTPUT_FILE" | grep -v '^$' | head -n 1)
        if [[ -n "$best" ]]; then
            echo -e "  Best endpoint: ${GREEN}$best${NC}"
        fi
    else
        echo -e "  No endpoints found. ${YELLOW}Run scan first.${NC}"
    fi
    
    echo ""
    echo -e "  Termux Info:"
    echo -e "    Architecture: $(uname -m)"
    echo -e "    Thread limit: $THREADS"
    echo -e "    Timeout: ${TIMEOUT}s"
}

# Show menu for Termux
show_menu() {
    clear
    print_header "WARP IP Finder for Termux v1.0"
    echo ""
    echo -e "  ${GREEN}1.${NC} Quick Scan (Recommended)"
    echo -e "  ${GREEN}2.${NC} Full Scan (Slow)"
    echo -e "  ${GREEN}3.${NC} Show Results"
    echo -e "  ${GREEN}4.${NC} Generate Configuration"
    echo -e "  ${GREEN}5.${NC} Test Best Endpoint"
    echo -e "  ${GREEN}6.${NC} Configure Settings"
    echo -e "  ${GREEN}7.${NC} Show Status"
    echo -e "  ${GREEN}8.${NC} Clear Results"
    echo -e "  ${GREEN}0.${NC} Exit"
    echo ""
    show_status
    echo ""
}

# Test the best endpoint
test_best() {
    print_header "Testing Best Endpoint"
    
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        print_error "No endpoints found. Run scan first."
        return 1
    fi
    
    local best=$(grep -v '^#' "$OUTPUT_FILE" | grep -v '^$' | head -n 1)
    
    if [[ -z "$best" ]]; then
        print_error "No valid endpoints found"
        return 1
    fi
    
    print_info "Testing: $best"
    echo ""
    
    local ip=$(echo $best | cut -d: -f1)
    local port=$(echo $best | cut -d: -f2)
    
    # Multiple tests
    local total=5
    local sum=0
    local success=0
    
    for i in $(seq 1 $total); do
        printf "  Test #$i ... "
        local result=$(test_endpoint $ip $port)
        local latency=$(echo $result | cut -d'|' -f2)
        local status=$(echo $result | cut -d'|' -f3)
        
        if [[ $status == "SUCCESS" ]]; then
            echo -e "${GREEN}OK${NC} (${latency}ms)"
            sum=$((sum + latency))
            success=$((success + 1))
        else
            echo -e "${RED}FAILED${NC}"
        fi
        sleep 1
    done
    
    echo ""
    if [[ $success -gt 0 ]]; then
        local avg=$((sum / success))
        print_success "Success rate: $success/$total"
        print_success "Average latency: ${avg}ms"
    else
        print_error "All tests failed - endpoint may be down"
    fi
}

# Configure settings
configure_settings() {
    print_header "Configure Settings"
    
    echo -e "  Current threads: ${GREEN}$THREADS${NC}"
    read -p "  Enter new thread count (1-20, default $THREADS): " new_threads
    if [[ -n "$new_threads" && $new_threads -ge 1 && $new_threads -le 20 ]]; then
        THREADS=$new_threads
        print_success "Threads set to $THREADS"
    fi
    
    echo ""
    echo -e "  Current timeout: ${GREEN}${TIMEOUT}s${NC}"
    read -p "  Enter new timeout (1-10, default $TIMEOUT): " new_timeout
    if [[ -n "$new_timeout" && $new_timeout -ge 1 && $new_timeout -le 10 ]]; then
        TIMEOUT=$new_timeout
        print_success "Timeout set to ${TIMEOUT}s"
    fi
}

# Clear results
clear_results() {
    print_header "Clear Results"
    read -p "Are you sure? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -f "$OUTPUT_FILE" "$RESULTS_FILE" "$CONFIG_FILE"
        print_success "All results cleared"
    else
        print_info "Cancelled"
    fi
}

# Main function for Termux
main() {
    # Check dependencies first
    check_dependencies
    
    while true; do
        show_menu
        read -p "Enter your choice: " choice
        
        case $choice in
            1)
                quick_scan
                ;;
            2)
                full_scan
                ;;
            3)
                if [[ -f "$RESULTS_FILE" ]]; then
                    cat "$RESULTS_FILE"
                else
                    print_error "No results found"
                fi
                ;;
            4)
                generate_config
                ;;
            5)
                test_best
                ;;
            6)
                configure_settings
                ;;
            7)
                show_status
                ;;
            8)
                clear_results
                ;;
            0)
                print_success "Goodbye from Termux!"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Run main function
main "$@"
