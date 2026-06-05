#!/bin/bash

## ---------------------------
## WARP IP Finder v1.0
## Find optimal Cloudflare WARP endpoints
## ---------------------------

# Color definitions
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# Default settings
THREADS=${THREADS:-50}
TIMEOUT=${TIMEOUT:-3}
OUTPUT_FILE="warp_endpoints.txt"
RESULTS_FILE="warp_results.csv"
PORT_RANGES=("2408" "500" "1701" "4500")
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

WARP_IPV6_RANGES=(
    "2606:4700:4700::/48"
    "2a06:98c0:3600::/48"
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

print_result() {
    echo -e "${WHITE}$1${NC} ${GREEN}$2${NC} ${YELLOW}$3${NC}"
}

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    local missing=()
    
    for cmd in curl ping bc sort awk; do
        if ! command -v $cmd &> /dev/null; then
            missing+=($cmd)
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        print_info "Installing missing dependencies..."
        
        if command -v apt &> /dev/null; then
            sudo apt update && sudo apt install -y bc curl
        elif command -v yum &> /dev/null; then
            sudo yum install -y bc curl
        elif command -v apk &> /dev/null; then
            sudo apk add bc curl
        fi
    fi
    
    print_success "All dependencies satisfied"
}

# Generate random IP from CIDR range
generate_ips() {
    local cidr=$1
    local count=${2:-10}
    local ips=()
    
    # Parse CIDR
    local ip=$(echo $cidr | cut -d/ -f1)
    local prefix=$(echo $cidr | cut -d/ -f2)
    
    # Convert IP to integer
    local IFS=.
    read -r a b c d <<< "$ip"
    local ip_int=$(( (a << 24) + (b << 16) + (c << 8) + d ))
    
    local mask=$(( 0xFFFFFFFF << (32 - prefix) ))
    local network=$(( ip_int & mask ))
    local broadcast=$(( network | ~mask & 0xFFFFFFFF ))
    local host_min=$(( network + 1 ))
    local host_max=$(( broadcast - 1 ))
    local total_hosts=$(( host_max - host_min + 1 ))
    
    for ((i=0; i<count && i<total_hosts; i++)); do
        local rand_offset=$(( RANDOM % total_hosts ))
        local host_int=$(( host_min + rand_offset ))
        
        # Convert back to IP
        local ip_out="$(( (host_int >> 24) & 0xFF )).$(( (host_int >> 16) & 0xFF )).$(( (host_int >> 8) & 0xFF )).$(( host_int & 0xFF ))"
        ips+=($ip_out)
    done
    
    echo "${ips[@]}"
}

# Generate random IPv6 from CIDR
generate_ipv6() {
    local cidr=$1
    local ip=$(echo $cidr | cut -d/ -f1)
    
    # Generate random IPv6 suffix
    local suffix=$(printf '%x%x:%x%x:%x%x:%x%x' \
        $((RANDOM % 65536)) $((RANDOM % 65536)) \
        $((RANDOM % 65536)) $((RANDOM % 65536)) \
        $((RANDOM % 65536)) $((RANDOM % 65536)) \
        $((RANDOM % 65536)) $((RANDOM % 65536)))
    
    echo "${ip}${suffix}"
}

# Test a single endpoint
test_endpoint() {
    local ip=$1
    local port=$2
    local protocol=${3:-"udp"}
    
    local start_time=$(date +%s%N)
    
    if [[ $protocol == "tcp" ]]; then
        timeout $TIMEOUT bash -c "echo >/dev/tcp/$ip/$port" 2>/dev/null
        local result=$?
    else
        timeout $TIMEOUT bash -c "echo test | nc -u -w1 $ip $port" 2>/dev/null
        local result=$?
    fi
    
    local end_time=$(date +%s%N)
    local latency=$(( (end_time - start_time) / 1000000 ))
    
    if [[ $result -eq 0 ]]; then
        echo "$ip:$port|$latency|SUCCESS"
    else
        echo "$ip:$port|$latency|FAILED"
    fi
}

# Test endpoint with curl (HTTPS)
test_https_endpoint() {
    local ip=$1
    local port=$2
    
    local start_time=$(date +%s%N)
    local response=$(timeout $TIMEOUT curl -s -o /dev/null -w "%{http_code}" \
        -x socks5h://$ip:$port \
        https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null)
    local end_time=$(date +%s%N)
    local latency=$(( (end_time - start_time) / 1000000 ))
    
    if [[ $response -eq 200 ]]; then
        local warp_status=$(curl -s -x socks5h://$ip:$port \
            https://www.cloudflare.com/cdn-cgi/trace 2>/dev/null | \
            grep warp | cut -d= -f2)
        echo "$ip:$port|$latency|$warp_status"
    else
        echo "$ip:$port|$latency|FAILED"
    fi
}

# Scan endpoints in parallel
scan_endpoints() {
    local ips=("$@")
    local total=${#ips[@]}
    local completed=0
    local results=()
    
    print_info "Scanning $total endpoints with $THREADS threads..."
    
    # Create temp directory for parallel processing
    local temp_dir=$(mktemp -d)
    
    # Process endpoints in batches
    for ((i=0; i<total; i+=THREADS)); do
        local batch=()
        for ((j=i; j<i+THREADS && j<total; j++)); do
            batch+=("${ips[$j]}")
        done
        
        # Test batch in parallel
        for endpoint in "${batch[@]}"; do
            (
                local ip=$(echo $endpoint | cut -d: -f1)
                local port=$(echo $endpoint | cut -d: -f2)
                local result=$(test_endpoint $ip $port)
                echo "$result" > "$temp_dir/result_$$_$RANDOM.txt"
            ) &
        done
        
        wait
        
        # Collect results
        for result_file in "$temp_dir"/result_* 2>/dev/null; do
            if [[ -f "$result_file" ]]; then
                local result=$(cat "$result_file")
                results+=("$result")
                ((completed++))
                
                # Show progress
                printf "\r${YELLOW}Progress: $completed/$total (${GREEN}$((completed * 100 / total))%${YELLOW})${NC}"
                rm -f "$result_file"
            fi
        done
    done
    
    printf "\n"
    rm -rf "$temp_dir"
    
    # Sort results by latency
    printf "%s\n" "${results[@]}" | sort -t'|' -k2 -n
}

# Generate IP list from ranges
generate_ip_list() {
    local use_ipv6=${1:-false}
    local ips=()
    
    if [[ "$use_ipv6" == "true" ]]; then
        print_info "Generating IPv6 addresses..."
        for range in "${WARP_IPV6_RANGES[@]}"; do
            for i in {1..20}; do
                local ip=$(generate_ipv6 "$range")
                for port in "${DEFAULT_PORTS[@]}"; do
                    ips+=("$ip:$port")
                done
            done
        done
    else
        print_info "Generating IPv4 addresses..."
        for range in "${WARP_IPV4_RANGES[@]}"; do
            local random_ips=($(generate_ips "$range" 50))
            for ip in "${random_ips[@]}"; do
                for port in "${DEFAULT_PORTS[@]}"; do
                    ips+=("$ip:$port")
                done
            done
        done
    fi
    
    echo "${ips[@]}"
}

# Quick scan mode
quick_scan() {
    print_header "Quick WARP Endpoint Scan"
    
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
    
    local results=()
    for endpoint in "${known_endpoints[@]}"; do
        echo -n "Testing $endpoint... "
        local result=$(test_endpoint $(echo $endpoint | tr ':' ' '))
        local status=$(echo $result | cut -d'|' -f3)
        local latency=$(echo $result | cut -d'|' -f2)
        
        if [[ $status == "SUCCESS" ]]; then
            echo -e "${GREEN}OK${NC} (${latency}ms)"
            results+=("$result")
        else
            echo -e "${RED}FAILED${NC}"
        fi
    done
    
    # Save results
    save_results "${results[@]}"
}

# Full scan mode
full_scan() {
    print_header "Full WARP Endpoint Scan"
    
    echo -e "${YELLOW}Select IP version:${NC}"
    echo -e "  ${GREEN}1.${NC} IPv4 Only"
    echo -e "  ${GREEN}2.${NC} IPv6 Only"
    echo -e "  ${GREEN}3.${NC} Both"
    read -p "Enter choice [1-3]: " ip_version
    
    local ips=()
    
    case $ip_version in
        1)
            ips+=($(generate_ip_list false))
            ;;
        2)
            ips+=($(generate_ip_list true))
            ;;
        3)
            ips+=($(generate_ip_list false))
            ips+=($(generate_ip_list true))
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    # Remove duplicates
    ips=($(printf "%s\n" "${ips[@]}" | sort -u))
    
    print_info "Total endpoints to test: ${#ips[@]}"
    read -p "Continue? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Scan cancelled"
        return
    fi
    
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

# Latency test mode
latency_test() {
    print_header "WARP Endpoint Latency Test"
    
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        print_error "No endpoints found. Run scan first."
        return 1
    fi
    
    print_info "Testing latency for endpoints in $OUTPUT_FILE..."
    
    local results=()
    while IFS= read -r endpoint; do
        if [[ -n "$endpoint" && ! "$endpoint" =~ ^# ]]; then
            echo -n "Testing $endpoint... "
            local result=$(test_endpoint $(echo $endpoint | tr ':' ' '))
            local latency=$(echo $result | cut -d'|' -f2)
            local status=$(echo $result | cut -d'|' -f3)
            
            if [[ $status == "SUCCESS" ]]; then
                echo -e "${GREEN}OK${NC} (${latency}ms)"
                results+=("$result")
            else
                echo -e "${RED}FAILED${NC}"
            fi
        fi
    done < "$OUTPUT_FILE"
    
    # Sort by latency and save
    printf "%s\n" "${results[@]}" | sort -t'|' -k2 -n > "$RESULTS_FILE"
    print_success "Latency test results saved to $RESULTS_FILE"
}

# Save results to file
save_results() {
    local results=("$@")
    
    if [[ ${#results[@]} -eq 0 ]]; then
        print_error "No successful endpoints found"
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
    
    print_success "Results saved to $OUTPUT_FILE and $RESULTS_FILE"
    
    # Display top 10 results
    echo ""
    print_header "Top 10 WARP Endpoints"
    echo -e "${CYAN}Rank | Endpoint | Latency${NC}"
    echo -e "${CYAN}-----|----------|--------${NC}"
    
    local rank=1
    for result in "${sorted[@]:0:10}"; do
        local endpoint=$(echo $result | cut -d'|' -f1)
        local latency=$(echo $result | cut -d'|' -f2)
        printf "%-4d | %-15s | ${GREEN}%dms${NC}\n" $rank "$endpoint" $latency
        ((rank++))
    done
}

# Generate config from best endpoint
generate_config() {
    print_header "Generate WARP Configuration"
    
    if [[ ! -f "$OUTPUT_FILE" ]]; then
        print_error "No endpoints found. Run scan first."
        return 1
    fi
    
    local best_endpoint=$(head -n 3 "$OUTPUT_FILE" | tail -n 1)
    
    if [[ -z "$best_endpoint" ]]; then
        print_error "No valid endpoints found"
        return 1
    fi
    
    echo ""
    print_info "Best endpoint: $best_endpoint"
    echo ""
    
    # Generate WGCF config
    cat << EOF
# WGCF Configuration
# Place this in /etc/wireguard/wgcf.conf

[Peer]
Endpoint = $best_endpoint
# Add other peer configuration as needed

# Or use with warp-cli:
# warp-cli set-custom-endpoint $best_endpoint

# For WARP-GO:
# Add to /opt/warp-go/warp.conf:
Endpoint = $best_endpoint
EOF
    
    echo ""
    print_info "To use this endpoint with WARP-Cli:"
    echo -e "  ${GREEN}warp-cli set-custom-endpoint $best_endpoint${NC}"
    
    echo ""
    print_info "To use with WARP-GO:"
    echo -e "  ${GREEN}sed -i 's/Endpoint.*/Endpoint = $best_endpoint/' /opt/warp-go/warp.conf${NC}"
    
    echo ""
    print_info "To use with WGCF:"
    echo -e "  ${GREEN}sed -i 's/engage.cloudflareclient.com:2408/$best_endpoint/' /etc/wireguard/wgcf.conf${NC}"
}

# Continuous monitoring mode
monitor_mode() {
    print_header "Continuous WARP Monitoring"
    
    local interval=${1:-60}
    
    print_info "Monitoring every $interval seconds. Press Ctrl+C to stop."
    echo ""
    
    while true; do
        clear
        print_header "WARP Endpoint Status - $(date)"
        
        if [[ -f "$OUTPUT_FILE" ]]; then
            local best_endpoint=$(head -n 3 "$OUTPUT_FILE" | tail -n 1)
            
            if [[ -n "$best_endpoint" ]]; then
                echo -n "Testing $best_endpoint... "
                local result=$(test_endpoint $(echo $best_endpoint | tr ':' ' '))
                local latency=$(echo $result | cut -d'|' -f2)
                local status=$(echo $result | cut -d'|' -f3)
                
                if [[ $status == "SUCCESS" ]]; then
                    echo -e "${GREEN}OK${NC} (${latency}ms)"
                else
                    echo -e "${RED}FAILED${NC}"
                    print_info "Endpoint failed! Running quick scan..."
                    quick_scan
                fi
            fi
        else
            print_info "No endpoints found. Running initial scan..."
            quick_scan
        fi
        
        echo ""
        print_info "Next check in $interval seconds..."
        sleep $interval
    done
}

# Show menu
show_menu() {
    clear
    print_header "WARP IP Finder v1.0"
    echo ""
    echo -e "  ${GREEN}1.${NC} Quick Scan (Known endpoints)"
    echo -e "  ${GREEN}2.${NC} Full Scan (All IP ranges)"
    echo -e "  ${GREEN}3.${NC} Latency Test"
    echo -e "  ${GREEN}4.${NC} Generate Configuration"
    echo -e "  ${GREEN}5.${NC} Continuous Monitor Mode"
    echo -e "  ${GREEN}6.${NC} Configure Threads (Current: $THREADS)"
    echo -e "  ${GREEN}7.${NC} Configure Timeout (Current: ${TIMEOUT}s)"
    echo -e "  ${GREEN}0.${NC} Exit"
    echo ""
}

# Main function
main() {
    # Check dependencies
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
                latency_test
                ;;
            4)
                generate_config
                ;;
            5)
                monitor_mode
                ;;
            6)
                read -p "Enter number of threads (1-200): " THREADS
                [[ -z "$THREADS" || "$THREADS" -lt 1 ]] && THREADS=50
                [[ "$THREADS" -gt 200 ]] && THREADS=200
                print_success "Threads set to $THREADS"
                ;;
            7)
                read -p "Enter timeout in seconds (1-10): " TIMEOUT
                [[ -z "$TIMEOUT" || "$TIMEOUT" -lt 1 ]] && TIMEOUT=3
                [[ "$TIMEOUT" -gt 10 ]] && TIMEOUT=10
                print_success "Timeout set to ${TIMEOUT}s"
                ;;
            0)
                print_success "Goodbye!"
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
