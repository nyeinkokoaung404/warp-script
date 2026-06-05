#!/bin/bash

## ---------------------------
## CloudFlare WARP Management Script
## ---------------------------

# Set non-interactive installation mode for Debian/Ubuntu
export DEBIAN_FRONTEND=noninteractive

# Color definitions
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN='\033[0m'

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}

# Multi-method OS detection, exit if OS not supported
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'" "fedora" "alpine")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS" "Fedora" "Alpine")
PACKAGE_UPDATE=("apt-get update" "apt-get update" "yum -y update" "yum -y update" "yum -y update" "apk update -f")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install" "yum -y install" "apk add -f")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove" "yum -y autoremove" "apk del -f")

[[ $EUID -ne 0 ]] && red "Note: Please run this script as root user" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')")

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    if [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]]; then
        SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
    fi
done

[[ -z $SYSTEM ]] && red "Current VPS system not supported, please use a mainstream OS" && exit 1

# Install curl if not present
if [[ -z $(type -P curl) ]]; then
    if [[ ! $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} curl
fi

# Check system kernel version
main=$(uname -r | awk -F . '{print $1}')
minor=$(uname -r | awk -F . '{print $2}')
# Get OS version
OSID=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1)
# Check VPS virtualization
VIRT=$(systemd-detect-virt)

# WGCF configuration commands
wg1="sed -i '/0\.0\.0\.0\/0/d' /etc/wireguard/wgcf.conf" # IPv4
wg2="sed -i '/\:\:\/0/d' /etc/wireguard/wgcf.conf"       # IPv6
wg3="sed -i 's/1.1.1.1/1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,2606:4700:4700::1111,2606:4700:4700::1001,2001:4860:4860::8888,2001:4860:4860::8844/g' /etc/wireguard/wgcf.conf"
wg4="sed -i 's/1.1.1.1/2606:4700:4700::1111,2606:4700:4700::1001,2001:4860:4860::8888,2001:4860:4860::8844,1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4/g' /etc/wireguard/wgcf.conf"
wg5='sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 1.1.1.1 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostDown = ip -4 rule delete from $(ip route get 1.1.1.1 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf'
wg6='sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2606:4700:4700::1111 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostDown = ip -6 rule delete from $(ip route get 2606:4700:4700::1111 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf'
wg7='sed -i "7 s/^/PostUp = ip -4 rule add from $(ip route get 1.1.1.1 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostDown = ip -4 rule delete from $(ip route get 1.1.1.1 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostUp = ip -6 rule add from $(ip route get 2606:4700:4700::1111 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf && sed -i "7 s/^/PostDown = ip -6 rule delete from $(ip route get 2606:4700:4700::1111 | grep -oP '"'src \K\S+') lookup main\n/"'" /etc/wireguard/wgcf.conf'

# WARP-GO configuration commands
wgo1='sed -i "s#.*AllowedIPs.*#AllowedIPs = 0.0.0.0/0#g" /opt/warp-go/warp.conf'      # IPv4
wgo2='sed -i "s#.*AllowedIPs.*#AllowedIPs = ::/0#g" /opt/warp-go/warp.conf'           # IPv6
wgo3='sed -i "s#.*AllowedIPs.*#AllowedIPs = 0.0.0.0/0,::/0#g" /opt/warp-go/warp.conf' # Dual stack
wgo4='sed -i "/\[Script\]/a PostUp = ip -4 rule add from $(ip route get 1.1.1.1 | grep -oP "src \K\S+") lookup main\n" /opt/warp-go/warp.conf && sed -i "/\[Script\]/a PostDown = ip -4 rule delete from $(ip route get 1.1.1.1 | grep -oP "src \K\S+") lookup main\n" /opt/warp-go/warp.conf'
wgo5='sed -i "/\[Script\]/a PostUp = ip -6 rule add from $(ip route get 2606:4700:4700::1111 | grep -oP "src \K\S+") lookup main\n" /opt/warp-go/warp.conf && sed -i "/\[Script\]/a PostDown = ip -6 rule delete from $(ip route get 2606:4700:4700::1111 | grep -oP "src \K\S+") lookup main\n" /opt/warp-go/warp.conf'
wgo6='sed -i "/\[Script\]/a PostUp = ip -4 rule add from $(ip route get 1.1.1.1 | grep -oP "src \K\S+") lookup main\n" /opt/warp-go/warp.conf && sed -i "/\[Script\]/a PostDown = ip -4 rule delete from $(ip route get 1.1.1.1 | grep -oP "src \K\S+") lookup main\n" /opt/warp-go/warp.conf && sed -i "/\[Script\]/a PostUp = ip -6 rule add from $(ip route get 2606:4700:4700::1111 | grep -oP "src \K\S+") lookup main\n" /opt/warp-go/warp.conf && sed -i "/\[Script\]/a PostDown = ip -6 rule delete from $(ip route get 2606:4700:4700::1111 | grep -oP "src \K\S+") lookup main\n" /opt/warp-go/warp.conf'

# Detect VPS CPU architecture
archAffix() {
    case "$(uname -m)" in
        x86_64 | amd64) echo 'amd64' ;;
        armv8 | arm64 | aarch64) echo 'arm64' ;;
        s390x) echo 's390x' ;;
        *) red "Unsupported CPU architecture!" && exit 1 ;;
    esac
}

# Detect VPS outgoing IP
check_ip() {
    ipv4=$(curl -s4m8 ip.p3terx.com -k | sed -n 1p)
    ipv6=$(curl -s6m8 ip.p3terx.com -k | sed -n 1p)
}

# Detect VPS IP type
check_stack() {
    lan4=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
    lan6=$(ip route get 2606:4700:4700::1111 2>/dev/null | grep -oP 'src \K\S+')
    if [[ "$lan4" =~ ^([0-9]{1,3}\.){3} ]]; then
        ping -c2 -W3 1.1.1.1 >/dev/null 2>&1 && out4=1
    fi
    if [[ "$lan6" != "::1" && "$lan6" =~ ^([a-f0-9]{1,4}:){2,4}[a-f0-9]{1,4} ]]; then
        ping6 -c2 -w10 2606:4700:4700::1111 >/dev/null 2>&1 && out6=1
    fi
}

# Detect VPS WARP status
check_warp() {
    warp_v4=$(curl -s4m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
    warp_v6=$(curl -s6m8 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}

# Check WARP+ account quota
check_quota() {
    if [[ "$CHECK_TYPE" = 1 ]]; then
        # For WARP-Cli, use its built-in interface
        QUOTA=$(warp-cli --accept-tos account 2>/dev/null | grep -oP 'Quota: \K\d+')
    else
        # For WGCF or WARP-GO, extract from config files
        if [[ -e "/opt/warp-go/warp-go" ]]; then
            ACCESS_TOKEN=$(grep 'Token' /opt/warp-go/warp.conf | cut -d= -f2 | sed 's# ##g')
            DEVICE_ID=$(grep 'Device' /opt/warp-go/warp.conf | cut -d= -f2 | sed 's# ##g')
        fi
        if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
            ACCESS_TOKEN=$(grep 'access_token' /etc/wireguard/wgcf-account.toml | cut -d \' -f2)
            DEVICE_ID=$(grep 'device_id' /etc/wireguard/wgcf-account.toml | cut -d \' -f2)
        fi

        # Use API to get quota info
        API=$(curl -s "https://api.cloudflareclient.com/v0a884/reg/$DEVICE_ID" -H "User-Agent: okhttp/3.12.1" -H "Authorization: Bearer $ACCESS_TOKEN")
        QUOTA=$(grep -oP '"quota":\K\d+' <<<$API)
    fi

    # Convert quota units
    [[ $QUOTA -gt 10000000000000 ]] && QUOTA="$(echo "scale=2; $QUOTA/1000000000000" | bc) TB" || QUOTA="$(echo "scale=2; $QUOTA/1000000000" | bc) GB"
}

# Check if TUN module is enabled
check_tun() {
    TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
    if [[ ! $TUN =~ "in bad state"|"处于错误状态"|"ist in schlechter Verfassung" ]]; then
        if [[ $VIRT == lxc ]]; then
            if [[ $main -lt 5 ]] || [[ $minor -lt 6 ]]; then
                red "TUN module not enabled on this VPS, please enable it in the control panel"
                exit 1
            else
                return 0
            fi
        elif [[ $VIRT == "openvz" ]]; then
            wget -N --no-check-certificate https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/tun.sh && bash tun.sh
        else
            red "TUN module not enabled on this VPS, please enable it in the control panel"
            exit 1
        fi
    fi
}

# Set IPv4 / IPv6 priority
stack_priority() {
    [[ -e /etc/gai.conf ]] && sed -i '/^precedence \:\:ffff\:0\:0/d;/^label 2002\:\:\/16/d' /etc/gai.conf

    yellow "Select IPv4 / IPv6 priority"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} IPv4 Preferred"
    echo -e " ${GREEN}2.${PLAIN} IPv6 Preferred"
    echo -e " ${GREEN}3.${PLAIN} Default Priority ${YELLOW}(Default)${PLAIN}"
    echo ""
    read -rp "Please select [1-3]: " priority
    case $priority in
        1) echo "precedence ::ffff:0:0/96  100" >> /etc/gai.conf ;;
        2) echo "label 2002::/16   2" >> /etc/gai.conf ;;
        *) yellow "Will use VPS default IP priority" ;;
    esac
}

# Find optimal MTU value for VPS
check_mtu() {
    yellow "Detecting and setting optimal MTU value, please wait..."
    check_ip
    MTUy=1500
    MTUc=10
    if [[ -n ${ipv6} && -z ${ipv4} ]]; then
        ping='ping6'
        IP1='2606:4700:4700::1001'
        IP2='2001:4860:4860::8888'
    else
        ping='ping'
        IP1='1.1.1.1'
        IP2='8.8.8.8'
    fi
    while true; do
        if ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP1} >/dev/null 2>&1 || ${ping} -c1 -W1 -s$((${MTUy} - 28)) -Mdo ${IP2} >/dev/null 2>&1; then
            MTUc=1
            MTUy=$((${MTUy} + ${MTUc}))
        else
            MTUy=$((${MTUy} - ${MTUc}))
            if [[ ${MTUc} = 1 ]]; then
                break
            fi
        fi
        if [[ ${MTUy} -le 1360 ]]; then
            MTUy='1360'
            break
        fi
    done
    
    # Store optimal MTU value for later use
    MTU=$((${MTUy} - 80))

    green "Optimal MTU = $MTU has been set!"
}

# Find optimal Endpoint IP address for VPS
check_endpoint() {
    yellow "Detecting and setting optimal Endpoint IP, please wait about 1-2 minutes..."

    # Download endpoint optimization tool
    wget https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/warp-yxip/warp-linux-$(archAffix) -O warp >/dev/null 2>&1

    # Generate endpoint IP list based on VPS outgoing IP
    check_ip

    # Remove Linux thread limit for endpoint optimization
    ulimit -n 102400

    # Set permissions for endpoint optimization tool
    chmod +x warp

    # Start WARP Endpoint IP optimization tool
    if [[ -n $ipv4 ]]; then
        ./warp
    else
        ./warp -ipv6
    fi

    # Extract best endpoint IP from result.csv
    best_endpoint=$(cat result.csv | sed -n 2p | awk -F ',' '{print $1}')

    # Check if loss is 100.00%, if so replace with default endpoint IP
    endpoint_loss=$(cat result.csv | sed -n 2p | awk -F ',' '{print $2}')
    if [[ $endpoint_loss == "100.00%" ]]; then
        check_ip
        if [[ -z $ipv4 ]]; then
            best_endpoint="[2606:4700:4700::1111]:2408"
        else
            best_endpoint="162.159.193.10:2408"
        fi
    fi

    # Clean up optimization tool files
    rm -f warp result.csv

    green "Optimal Endpoint IP = $best_endpoint has been set!"
}

# Select WGCF installation / switch mode
select_wgcf() {
    yellow "Please select WGCF installation / switch mode"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Install / Switch WGCF-WARP single stack mode ${YELLOW}(IPv4)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Install / Switch WGCF-WARP single stack mode ${YELLOW}(IPv6)${PLAIN}"
    echo -e " ${GREEN}3.${PLAIN} Install / Switch WGCF-WARP dual stack mode"
    echo ""
    read -p "Enter option [1-3]: " wgcf_mode
    if [ "$wgcf_mode" = "1" ]; then
        install_wgcf_ipv4
    elif [ "$wgcf_mode" = "2" ]; then
        install_wgcf_ipv6
    elif [ "$wgcf_mode" = "3" ]; then
        install_wgcf_dual
    else
        red "Invalid input, please try again"
        select_wgcf
    fi
}

install_wgcf_ipv4() {
    # Check WARP status
    check_warp

    # Disable WARP if running
    if [[ -f "/opt/warp-go/warp-go" ]]; then
        systemctl stop warp-go
        systemctl disable warp-go
    elif [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf
    fi

    # Check for WARP-GO conflict
    if [[ -f "/opt/warp-go/warp-go" ]]; then
        red "WARP-GO is already installed, please uninstall WARP-GO first"
        exit 1
    fi

    check_stack

    # Select appropriate mode based on detection results
    if [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]]; then
        # IPv4 Only
        wgcf1=$wg2 && wgcf2=$wg3 && wgcf3=$wg5
    elif [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # IPv6 Only
        wgcf1=$wg2 && wgcf2=$wg4
    elif [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]]; then
        # Dual Stack
        wgcf1=$wg2 && wgcf2=$wg3 && wgcf3=$wg5
    elif [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # NAT IPv4 + IPv6
        wgcf1=$wg2 && wgcf2=$wg4 && wgcf3=$wg5
    fi

    # Install or switch WGCF
    if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        switch_wgcf_conf
    else
        install_wgcf
    fi
}

install_wgcf_ipv6() {
    check_warp

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        systemctl stop warp-go
        systemctl disable warp-go
    elif [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf
    fi

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        red "WARP-GO is already installed, please uninstall WARP-GO first"
        exit 1
    fi

    check_stack

    if [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]]; then
        # IPv4 Only
        wgcf1=$wg1 && wgcf2=$wg3
    elif [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # IPv6 Only
        wgcf1=$wg1 && wgcf2=$wg4 && wgcf3=$wg6
    elif [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]]; then
        # Dual Stack
        wgcf1=$wg1 && wgcf2=$wg3 && wgcf3=$wg6
    elif [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # NAT IPv4 + IPv6
        wgcf1=$wg1 && wgcf2=$wg4 && wgcf3=$wg6
    fi

    if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        switch_wgcf_conf
    else
        install_wgcf
    fi
}

install_wgcf_dual() {
    check_warp

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        systemctl stop warp-go
        systemctl disable warp-go
    elif [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf
    fi

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        red "WARP-GO is already installed, please uninstall WARP-GO first"
        exit 1
    fi

    check_stack

    if [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]]; then
        # IPv4 Only
        wgcf1=$wg3 && wgcf2=$wg5
    elif [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # IPv6 Only
        wgcf1=$wg4 && wgcf2=$wg6
    elif [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]]; then
        # Dual Stack
        wgcf1=$wg3 && wgcf2=$wg7
    elif [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # NAT IPv4 + IPv6
        wgcf1=$wg4 && wgcf2=$wg6
    fi

    if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        switch_wgcf_conf
    else
        install_wgcf
    fi
}

# Download WGCF
init_wgcf() {
    wget --no-check-certificate https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/wgcf/wgcf-latest-linux-$(archAffix) -O /usr/local/bin/wgcf
    chmod +x /usr/local/bin/wgcf
}

# Register CloudFlare WARP account using WGCF
register_wgcf() {
    if [[ $country4 == "Russia" || $country6 == "Russia" ]]; then
        # Download WARP API tool
        wget https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/warp-api/main-linux-$(archAffix)
        chmod +x main-linux-$(archAffix)

        arch=$(archAffix)
        result_output=$(./main-linux-$arch)

        device_id=$(echo "$result_output" | awk -F ': ' '/device_id/{print $2}')
        private_key=$(echo "$result_output" | awk -F ': ' '/private_key/{print $2}')
        warp_token=$(echo "$result_output" | awk -F ': ' '/token/{print $2}')
        license_key=$(echo "$result_output" | awk -F ': ' '/license/{print $2}')

        cat << EOF > wgcf-account.toml
access_token = '$warp_token'
device_id = '$device_id'
license_key = '$license_key'
private_key = '$private_key'
EOF

        rm -f main-linux-$(archAffix)
        wgcf generate && chmod +x wgcf-profile.conf
    else
        if [[ -f /etc/wireguard/wgcf-account.toml ]]; then
            cp -f /etc/wireguard/wgcf-account.toml /root/wgcf-account.toml
        fi

        until [[ -e wgcf-account.toml ]]; do
            yellow "Registering account with CloudFlare WARP, if you see 429 Too Many Requests error, please wait for script to retry"
            wgcf register --accept-tos
            sleep 5
        done
        chmod +x wgcf-account.toml
        wgcf generate && chmod +x wgcf-profile.conf
    fi
}

# Configure WGCF WireGuard configuration
conf_wgcf() {
    echo $wgcf1 | sh
    echo $wgcf2 | sh
    echo $wgcf3 | sh
}

# Check if WGCF started successfully
check_wgcf() {
    yellow "Starting WGCF-WARP"
    i=0
    while [ $i -le 4 ]; do
        let i++
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl start wg-quick@wgcf >/dev/null 2>&1
        check_warp
        if [[ $warp_v4 =~ on|plus ]] || [[ $warp_v6 =~ on|plus ]]; then
            green "WGCF-WARP started successfully!"
            systemctl enable wg-quick@wgcf >/dev/null 2>&1
            before_showinfo && show_info
            break
        else
            red "WGCF-WARP failed to start!"
        fi
        check_warp
        if [[ ! $warp_v4 =~ on|plus && ! $warp_v6 =~ on|plus ]]; then
            wg-quick down wgcf 2>/dev/null
            systemctl stop wg-quick@wgcf >/dev/null 2>&1
            systemctl disable wg-quick@wgcf >/dev/null 2>&1
            red "WGCF-WARP installation failed!"
            green "Suggestions:"
            yellow "1. Strongly recommend using official sources to upgrade system and kernel! If using third-party sources, please update to latest version or reset to official sources"
            yellow "2. Some VPS systems are extremely minimal, please install required dependencies manually and try again"
            yellow "3. Check https://www.cloudflarestatus.com/ - your VPS region may be in yellow 'Re-routed' status"
            yellow "4. WGCF is blocked by CloudFlare in Hong Kong and US West regions, please uninstall WGCF and try WARP-GO instead"
            exit 1
        fi
    done
}

install_wgcf() {
    [[ $SYSTEM == "CentOS" ]] && [[ ${OSID} -lt 7 ]] && yellow "Current system version: ${CMD} \nWGCF-WARP mode only supports CentOS / Almalinux / Rocky / Oracle Linux 7 and above" && exit 1
    [[ $SYSTEM == "Debian" ]] && [[ ${OSID} -lt 10 ]] && yellow "Current system version: ${CMD} \nWGCF-WARP mode only supports Debian 10 and above" && exit 1
    [[ $SYSTEM == "Fedora" ]] && [[ ${OSID} -lt 29 ]] && yellow "Current system version: ${CMD} \nWGCF-WARP mode only supports Fedora 29 and above" && exit 1
    [[ $SYSTEM == "Ubuntu" ]] && [[ ${OSID} -lt 18 ]] && yellow "Current system version: ${CMD} \nWGCF-WARP mode only supports Ubuntu 16.04 and above" && exit 1

    check_tun
    stack_priority

    # Install WGCF dependencies
    if [[ $SYSTEM == "Alpine" ]]; then
        ${PACKAGE_INSTALL[int]} sudo curl wget bash grep net-tools iproute2 openresolv openrc iptables ip6tables wireguard-tools
    fi
    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} epel-release
        ${PACKAGE_INSTALL[int]} sudo curl wget unzip iproute net-tools wireguard-tools iptables bc htop screen python3 iputils qrencode
        if [[ $OSID == 9 ]] && [[ -z $(type -P resolvconf) ]]; then
            wget -N https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/resolvconf -O /usr/sbin/resolvconf
            chmod +x /usr/sbin/resolvconf
        fi
    fi
    if [[ $SYSTEM == "Fedora" ]]; then
        ${PACKAGE_INSTALL[int]} sudo curl wget unzip iproute net-tools wireguard-tools iptables bc htop screen python3 iputils qrencode
    fi
    if [[ $SYSTEM == "Debian" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo wget curl unzip lsb-release bc htop screen python3 iputils-ping qrencode
        echo "deb http://deb.debian.org/debian $(lsb_release -sc)-backports main" | tee /etc/apt/sources.list.d/backports.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    fi
    if [[ $SYSTEM == "Ubuntu" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget unzip lsb-release bc htop screen python3 iputils-ping qrencode
        ${PACKAGE_INSTALL[int]} --no-install-recommends net-tools iproute2 openresolv dnsutils wireguard-tools iptables
    fi

    # Install Wireguard-GO for kernel < 5.6 or OpenVZ/LXC virtualization
    if [[ $main -lt 5 ]] || [[ $minor -lt 6 ]] || [[ $VIRT =~ lxc|openvz ]]; then
        wget -N --no-check-certificate https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/wireguard-go/wireguard-go-$(archAffix) -O /usr/bin/wireguard-go
        chmod +x /usr/bin/wireguard-go
    fi

    # Enable IPv6 support for IPv4-only VPS
    if [[ $(sysctl -a | grep 'disable_ipv6.*=.*1') || $(cat /etc/sysctl.{conf,d/*} | grep 'disable_ipv6.*=.*1') ]]; then
        sed -i '/disable_ipv6/d' /etc/sysctl.{conf,d/*}
        echo 'net.ipv6.conf.all.disable_ipv6 = 0' >/etc/sysctl.d/ipv6.conf
        sysctl -w net.ipv6.conf.all.disable_ipv6=0
    fi

    init_wgcf
    register_wgcf

    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi

    cp -f wgcf-profile.conf /etc/wireguard/wgcf.conf
    mv -f wgcf-profile.conf /etc/wireguard/wgcf-profile.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml

    conf_wgcf
    check_mtu
    sed -i "s/MTU.*/MTU = $MTU/g" /etc/wireguard/wgcf.conf
    check_endpoint
    sed -i "s/engage.cloudflareclient.com:2408/$best_endpoint/g" /etc/wireguard/wgcf.conf
    check_wgcf
}

switch_wgcf_conf() {
    wg-quick down wgcf 2>/dev/null
    systemctl stop wg-quick@wgcf 2>/dev/null
    systemctl disable wg-quick@wgcf 2>/dev/null

    rm -rf /etc/wireguard/wgcf.conf
    cp -f /etc/wireguard/wgcf-profile.conf /etc/wireguard/wgcf.conf >/dev/null 2>&1

    conf_wgcf
    check_mtu
    sed -i "s/MTU.*/MTU = $MTU/g" /etc/wireguard/wgcf.conf
    check_endpoint
    sed -i "s/engage.cloudflareclient.com:2408/$best_endpoint/g" /etc/wireguard/wgcf.conf
    check_wgcf
}

# Uninstall WGCF
uninstall_wgcf() {
    wg-quick down wgcf 2>/dev/null
    systemctl stop wg-quick@wgcf 2>/dev/null
    systemctl disable wg-quick@wgcf 2>/dev/null

    ${PACKAGE_UNINSTALL[int]} wireguard-tools

    if [[ -z $(type -P wireproxy) ]]; then
        rm -f /usr/local/bin/wgcf
        rm -f /etc/wireguard/wgcf-profile.toml
        rm -f /etc/wireguard/wgcf-account.toml
    fi

    rm -f /etc/wireguard/wgcf.conf
    rm -f /usr/bin/wireguard-go

    if [[ -e /etc/gai.conf ]]; then
        sed -i '/^precedence[ ]*::ffff:0:0\/96[ ]*100/d' /etc/gai.conf
    fi

    green "WGCF-WARP has been completely uninstalled!"
    before_showinfo && show_info
}

# Configure WARP-GO config
conf_wpgo() {
    echo $wpgo1 | sh
    echo $wpgo2 | sh
}

# Register WARP free account using WARP API
register_wpgo(){
    wget https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/warp-api/main-linux-$(archAffix)
    chmod +x main-linux-$(archAffix)

    arch=$(archAffix)
    result_output=$(./main-linux-$arch)

    device_id=$(echo "$result_output" | awk -F ': ' '/device_id/{print $2}')
    private_key=$(echo "$result_output" | awk -F ': ' '/private_key/{print $2}')
    warp_token=$(echo "$result_output" | awk -F ': ' '/token/{print $2}')

    cat << EOF > /opt/warp-go/warp.conf
[Account]
Device = $device_id
PrivateKey = $private_key
Token = $warp_token
Type = free
Name = WARP
MTU = 1280

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
Endpoint = 162.159.193.10:1701
# AllowedIPs = 0.0.0.0/0
# AllowedIPs = ::/0
KeepAlive = 30
EOF
    
    sed -i '0,/AllowedIPs/{/AllowedIPs/d;}' /opt/warp-go/warp.conf
    sed -i '/KeepAlive/a [Script]' /opt/warp-go/warp.conf

    rm -f main-linux-$(archAffix)
}

# Check if WARP-GO is running properly
check_wpgo() {
    yellow "Starting WARP-GO"
    i=0
    while [ $i -le 4 ]; do
        let i++
        kill -15 $(pgrep warp-go) >/dev/null 2>&1
        sleep 2
        systemctl stop warp-go
        systemctl disable warp-go >/dev/null 2>&1
        systemctl start warp-go
        systemctl enable warp-go >/dev/null 2>&1
        check_warp
        sleep 2
        if [[ $warp_v4 =~ on|plus ]] || [[ $warp_v6 =~ on|plus ]]; then
            green "WARP-GO started successfully!"
            before_showinfo && show_info
            break
        else
            red "WARP-GO failed to start!"
        fi

        check_warp
        if [[ ! $warp_v4 =~ on|plus && ! $warp_v6 =~ on|plus ]]; then
            systemctl stop warp-go
            systemctl disable warp-go >/dev/null 2>&1
            red "WARP-GO installation failed!"
            green "Suggestions:"
            yellow "1. Strongly recommend using official sources to upgrade system and kernel! If using third-party sources, please update to latest version or reset to official sources"
            yellow "2. Some VPS systems are extremely minimal, please install required dependencies manually and try again"
            exit 1
        fi
    done
}

# Select WARP-GO installation / switch mode
select_wpgo() {
    yellow "Please select WARP-GO installation / switch mode"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Install / Switch WARP-GO single stack mode ${YELLOW}(IPv4)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} Install / Switch WARP-GO single stack mode ${YELLOW}(IPv6)${PLAIN}"
    echo -e " ${GREEN}3.${PLAIN} Install / Switch WARP-GO dual stack mode"
    echo ""
    read -p "Enter option [1-3]: " wpgo_mode
    if [ "$wpgo_mode" = "1" ]; then
        install_wpgo_ipv4
    elif [ "$wpgo_mode" = "2" ]; then
        install_wpgo_ipv6
    elif [ "$wpgo_mode" = "3" ]; then
        install_wpgo_dual
    else
        red "Invalid input, please try again"
        select_wpgo
    fi
}

install_wpgo_ipv4() {
    check_warp

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        systemctl stop warp-go
        systemctl disable warp-go
    elif [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf
    fi

    if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        red "WGCF-WARP is already installed, please uninstall WGCF-WARP first"
        exit 1
    fi

    check_stack

    if [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]]; then
        # IPv4 Only
        wpgo1=$wgo1 && wpgo2=$wgo4
    elif [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # IPv6 Only
        wpgo1=$wgo1 && wpgo2=$wgo5
    elif [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]]; then
        # Dual Stack
        wpgo1=$wgo1 && wpgo2=$wgo6
    elif [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # NAT IPv4 + IPv6
        wpgo1=$wgo1 && wpgo2=$wgo6
    fi

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        switch_wpgo_conf
    else
        install_wpgo
    fi
}

install_wpgo_ipv6() {
    check_warp

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        systemctl stop warp-go
        systemctl disable warp-go
    elif [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf
    fi

    if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        red "WGCF-WARP is already installed, please uninstall WGCF-WARP first"
        exit 1
    fi

    check_stack

    if [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]]; then
        # IPv4 Only
        wpgo1=$wgo2 && wpgo2=$wgo4
    elif [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # IPv6 Only
        wpgo1=$wgo2 && wpgo2=$wgo5
    elif [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]]; then
        # Dual Stack
        wpgo1=$wgo2 && wpgo2=$wgo6
    elif [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # NAT IPv4 + IPv6
        wpgo1=$wgo2 && wpgo2=$wgo6
    fi

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        switch_wpgo_conf
    else
        install_wpgo
    fi
}

install_wpgo_dual() {
    check_warp

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        systemctl stop warp-go
        systemctl disable warp-go
    elif [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf
    fi

    if [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        red "WGCF-WARP is already installed, please uninstall WGCF-WARP first"
        exit 1
    fi

    check_stack

    if [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]]; then
        # IPv4 Only
        wpgo1=$wgo3 && wpgo2=$wgo4
    elif [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # IPv6 Only
        wpgo1=$wgo3 && wpgo2=$wgo5
    elif [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]]; then
        # Dual Stack
        wpgo1=$wgo3 && wpgo2=$wgo6
    elif [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        # NAT IPv4 + IPv6
        wpgo1=$wgo3 && wpgo2=$wgo6
    fi

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        switch_wpgo_conf
    else
        install_wpgo
    fi
}

install_wpgo() {
    check_tun
    stack_priority

    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} sudo curl wget bc htop iputils screen python3 qrencode
    elif [[ $SYSTEM == "Alpine" ]]; then
        ${PACKAGE_INSTALL[int]} sudo curl wget bash grep bc htop iputils screen python3 qrencode
    else
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget bc htop iputils-ping screen python3 qrencode
    fi

    if [[ $(sysctl -a | grep 'disable_ipv6.*=.*1') || $(cat /etc/sysctl.{conf,d/*} | grep 'disable_ipv6.*=.*1') ]]; then
        sed -i '/disable_ipv6/d' /etc/sysctl.{conf,d/*}
        echo 'net.ipv6.conf.all.disable_ipv6 = 0' >/etc/sysctl.d/ipv6.conf
        sysctl -w net.ipv6.conf.all.disable_ipv6=0
    fi

    mkdir -p /opt/warp-go/
    wget -O /opt/warp-go/warp-go https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/warp-go/warp-go-latest-linux-$(archAffix)
    chmod +x /opt/warp-go/warp-go

    register_wpgo
    conf_wpgo
    check_mtu
    sed -i "s/MTU.*/MTU = $MTU/g" /opt/warp-go/warp.conf
    check_endpoint
    sed -i "/Endpoint/s/.*/Endpoint = "$best_endpoint"/" /opt/warp-go/warp.conf

    cat << EOF > /lib/systemd/system/warp-go.service
[Unit]
Description=warp-go service
After=network.target
Documentation=https://gitlab.com/Misaka-blog/warp-script
Documentation=https://gitlab.com/ProjectWARP/warp-go

[Service]
WorkingDirectory=/opt/warp-go/
ExecStart=/opt/warp-go/warp-go --config=/opt/warp-go/warp.conf
Environment="LOG_LEVEL=verbose"
RemainAfterExit=yes
Restart=always

[Install]
WantedBy=multi-user.target
EOF

    check_wpgo
}

switch_wpgo_conf() {
    systemctl stop warp-go
    systemctl disable warp-go
    conf_wpgo
    check_wpgo
}

uninstall_wpgo() {
    systemctl stop warp-go
    systemctl disable --now warp-go >/dev/null 2>&1
    kill -15 $(pgrep warp-go) >/dev/null 2>&1
    /opt/warp-go/warp-go --config=/opt/warp-go/warp.conf --remove >/dev/null 2>&1
    rm -rf /opt/warp-go /tmp/warp-go* /lib/systemd/system/warp-go.service
    green "WARP-GO has been completely uninstalled!"
}

check_warp_cli(){
    warp-cli --accept-tos connect >/dev/null 2>&1
    warp-cli --accept-tos enable-always-on >/dev/null 2>&1
    sleep 2
    if [[ ! $(ss -nltp) =~ 'warp-svc' ]]; then
        red "WARP-Cli proxy mode installation failed"
        green "Suggestions:"
        yellow "1. Strongly recommend using official sources to upgrade system and kernel! If using third-party sources, please update to latest version or reset to official sources"
        yellow "2. Some VPS systems are extremely minimal, please install required dependencies manually and try again"
        exit 1
    else
        green "WARP-Cli proxy mode started successfully!"
        before_showinfo && show_info
    fi
}

install_warp_cli() {
    [[ $SYSTEM == "CentOS" ]] && [[ ! ${OSID} =~ 8|9 ]] && yellow "Current system version: ${CMD} \nWARP-Cli proxy mode only supports CentOS / Almalinux / Rocky / Oracle Linux 8/9" && exit 1
    [[ $SYSTEM == "Debian" ]] && [[ ! ${OSID} =~ 9|10|11|12 ]] && yellow "Current system version: ${CMD} \nWARP-Cli proxy mode only supports Debian 9-12" && exit 1
    [[ $SYSTEM == "Fedora" ]] && yellow "Current system version: ${CMD} \nWARP-Cli does not support Fedora yet" && exit 1
    [[ $SYSTEM == "Ubuntu" ]] && [[ ! ${OSID} =~ 16|18|20|22 ]] && yellow "Current system version: ${CMD} \nWARP-Cli proxy mode only supports Ubuntu 16.04/18.04/20.04/22.04" && exit 1

    [[ ! $(archAffix) == "amd64" ]] && red "WARP-Cli does not support your VPS CPU architecture yet, please use amd64 VPS" && exit 1

    check_tun

    if [[ ! $(archAffix) == "amd64" ]]; then
        red "WARP-Cli does not support your VPS CPU architecture yet, please use amd64 VPS" && exit 1
    fi

    check_stack
    if [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]]; then
        red "WARP-Cli does not support IPv6-only VPS yet, please use a VPS with IPv4 network" && exit 1
    fi

    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} epel-release
        ${PACKAGE_INSTALL[int]} sudo curl wget net-tools bc htop iputils screen python3 qrencode
        rpm -ivh http://pkg.cloudflareclient.com/cloudflare-release-el8.rpm
        ${PACKAGE_INSTALL[int]} cloudflare-warp
    fi
    if [[ $SYSTEM == "Debian" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget lsb-release bc htop iputils-ping screen python3 qrencode
        [[ -z $(type -P gpg 2>/dev/null) ]] && ${PACKAGE_INSTALL[int]} gnupg
        [[ -z $(apt list 2>/dev/null | grep apt-transport-https | grep installed) ]] && ${PACKAGE_INSTALL[int]} apt-transport-https
        curl https://pkg.cloudflareclient.com/pubkey.gpg | apt-key add -
        echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} cloudflare-warp
    fi
    if [[ $SYSTEM == "Ubuntu" ]]; then
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget lsb-release bc htop iputils-ping screen python3 qrencode
        curl https://pkg.cloudflareclient.com/pubkey.gpg | apt-key add -
        echo "deb http://pkg.cloudflareclient.com/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/cloudflare-client.list
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} cloudflare-warp
    fi

    read -rp "Enter port for WARP-Cli proxy mode (default random port): " port
    [[ -z $port ]] && port=$(shuf -i 1000-65535 -n 1)
    if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
        until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; do
            if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
                yellow "Port is already in use, please enter a different port"
                read -rp "Enter port for WARP-Cli proxy mode (default random port): " port
            fi
        done
    fi

    warp-cli --accept-tos register >/dev/null 2>&1
    warp-cli --accept-tos set-mode proxy >/dev/null 2>&1
    warp-cli --accept-tos set-proxy-port "$port" >/dev/null 2>&1
    check_endpoint
    warp-cli --accept-tos set-custom-endpoint "$best_endpoint" >/dev/null 2>&1
    check_warp_cli
}

uninstall_warp_cli() {
    warp-cli --accept-tos disconnect >/dev/null 2>&1
    warp-cli --accept-tos disable-always-on >/dev/null 2>&1
    warp-cli --accept-tos delete >/dev/null 2>&1
    systemctl disable --now warp-svc >/dev/null 2>&1
    ${PACKAGE_UNINSTALL[int]} cloudflare-warp
    green "WARP-Cli client has been completely uninstalled!"
    before_showinfo && show_info
}

check_wireproxy(){
    yellow "Starting WireProxy-WARP proxy mode"
    systemctl start wireproxy-warp
    wireproxy_status=$(curl -sx socks5h://localhost:$port https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
    sleep 2
    retry_time=0
    until [[ $wireproxy_status =~ on|plus ]]; do
        retry_time=$((${retry_time} + 1))
        red "WireProxy-WARP proxy mode failed to start, attempting restart, attempt: $retry_time"
        systemctl stop wireproxy-warp
        systemctl start wireproxy-warp
        wireproxy_status=$(curl -sx socks5h://localhost:$port https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
        if [[ $retry_time == 6 ]]; then
            echo ""
            red "WireProxy-WARP proxy mode installation failed!"
            green "Suggestions:"
            yellow "1. Strongly recommend using official sources to upgrade system and kernel! If using third-party sources, please update to latest version or reset to official sources"
            yellow "2. Some VPS systems are extremely minimal, please install required dependencies manually and try again"
            yellow "3. Check https://www.cloudflarestatus.com/ - your VPS region may be in yellow 'Re-routed' status"
            yellow "4. WGCF is blocked by CloudFlare in Hong Kong and US West regions"
            exit 1
        fi
        sleep 8
    done
    sleep 5
    systemctl enable wireproxy-warp >/dev/null 2>&1
    green "WireProxy-WARP proxy mode started successfully!"
    before_showinfo && show_info
}

install_wireproxy() {
    if [[ $SYSTEM == "CentOS" ]]; then
        ${PACKAGE_INSTALL[int]} sudo curl wget bc htop iputils screen python3 qrencode wireguard-tools
    elif [[ $SYSTEM == "Alpine" ]]; then
        ${PACKAGE_INSTALL[int]} sudo curl wget bash grep bc htop iputils screen python3 qrencode wireguard-tools
    else
        ${PACKAGE_UPDATE[int]}
        ${PACKAGE_INSTALL[int]} sudo curl wget bc htop iputils-ping screen python3 qrencode wireguard-tools
    fi

    wget -N https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/wireproxy/wireproxy-latest-linux-$(archAffix) -O /usr/local/bin/wireproxy
    chmod +x /usr/local/bin/wireproxy

    read -rp "Enter port for WireProxy-WARP proxy mode (default random port): " port
    [[ -z $port ]] && port=$(shuf -i 1000-65535 -n 1)
    if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
        until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; do
            if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
                yellow "Port is already in use, please enter a different port"
                read -rp "Enter port for WireProxy-WARP proxy mode (default random port): " port
            fi
        done
    fi

    init_wgcf
    register_wgcf

    public_key=$(grep PublicKey wgcf-profile.conf | sed "s/PublicKey = //g")
    private_key=$(grep PrivateKey wgcf-profile.conf | sed "s/PrivateKey = //g")

    if [[ ! -d "/etc/wireguard" ]]; then
        mkdir /etc/wireguard
    fi

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        systemctl stop warp-go
        systemctl disable warp-go
    elif [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf
    fi

    check_mtu
    check_endpoint

    if [[ -f "/opt/warp-go/warp-go" ]]; then
        systemctl start warp-go
        systemctl enable warp-go
    elif [[ -n $(type -P wg-quick) && -n $(type -P wgcf) ]]; then
        wg-quick up wgcf >/dev/null 2>&1
        systemctl enable wg-quick@wgcf
    fi

    cat << EOF > /etc/wireguard/proxy.conf
[Interface]
Address = 172.16.0.2/32
MTU = $MTU
PrivateKey = $private_key
DNS = 1.1.1.1,1.0.0.1,8.8.8.8,8.8.4.4,2606:4700:4700::1001,2606:4700:4700::1111,2001:4860:4860::8888,2001:4860:4860::8844
[Peer]
PublicKey = $public_key
Endpoint = $best_endpoint
[Socks5]
BindAddress = 127.0.0.1:$port
EOF
    mv -f wgcf-profile.conf /etc/wireguard/wgcf-profile.conf
    mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml

    cat <<'TEXT' >/etc/systemd/system/wireproxy-warp.service
[Unit]
Description=CloudFlare WARP Socks5 proxy mode based for WireProxy, script by Misaka-blog
After=network.target
[Install]
WantedBy=multi-user.target
[Service]
Type=simple
WorkingDirectory=/root
ExecStart=/usr/local/bin/wireproxy -c /etc/wireguard/proxy.conf
Restart=always
TEXT

    check_wireproxy
}

uninstall_wireproxy() {
    systemctl stop wireproxy-warp
    systemctl disable wireproxy-warp
    ${PACKAGE_UNINSTALL[int]} wireguard-tools
    rm -f /etc/systemd/system/wireproxy-warp.service /usr/local/bin/wireproxy /etc/wireguard/proxy.conf
    if [[ ! -f /etc/wireguard/wgcf.conf ]]; then
        rm -f /usr/local/bin/wgcf /etc/wireguard/wgcf-account.toml
    fi
    green "WireProxy-WARP proxy mode has been completely uninstalled!"
    before_showinfo && show_info
}

change_warp_port() {
    yellow "Please select WARP client to modify port"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} WARP-Cli"
    echo -e " ${GREEN}2.${PLAIN} WireProxy"
    echo ""
    read -p "Enter option [1-2]: " chport_mode
    if [[ $chport_mode == 1 ]]; then
        if [[ $(warp-cli --accept-tos status) =~ Connected ]]; then
            warp-cli --accept-tos disconnect >/dev/null 2>&1
        fi

        read -rp "Enter port for WARP-Cli proxy mode (default random port): " port
        [[ -z $port ]] && port=$(shuf -i 1000-65535 -n 1)
        if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
            until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; do
                if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
                    yellow "Port is already in use, please enter a different port"
                    read -rp "Enter port for WARP-Cli proxy mode (default random port): " port
                fi
            done
        fi

        warp-cli --accept-tos set-proxy-port "$port" >/dev/null 2>&1
        check_warp_cli
    elif [[ $chport_mode == 2 ]]; then
        if [[ -n $(ss -nltp | grep wireproxy) ]]; then
            systemctl stop wireproxy-warp
        fi

        read -rp "Enter port for WireProxy-WARP proxy mode (default random port): " port
        [[ -z $port ]] && port=$(shuf -i 1000-65535 -n 1)
        if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
            until [[ -z $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; do
                if [[ -n $(ss -ntlp | awk '{print $4}' | grep -w "$port") ]]; then
                    yellow "Port is already in use, please enter a different port"
                    read -rp "Enter port for WireProxy-WARP proxy mode (default random port): " port
                fi
            done
        fi

        current_port=$(grep BindAddress /etc/wireguard/proxy.conf)
        sed -i "s/$current_port/BindAddress = 127.0.0.1:$port/g" /etc/wireguard/proxy.conf
        check_wireproxy
    else
        red "Invalid input, please try again"
        change_warp_port
    fi
}

switch_warp() {
    yellow "Please select WARP client operation"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Start WGCF-WARP"
    echo -e " ${GREEN}2.${PLAIN} Stop WGCF-WARP"
    echo -e " ${GREEN}3.${PLAIN} Restart WGCF-WARP"
    echo -e " ${GREEN}4.${PLAIN} Start WARP-GO"
    echo -e " ${GREEN}5.${PLAIN} Stop WARP-GO"
    echo -e " ${GREEN}6.${PLAIN} Restart WARP-GO"
    echo -e " ${GREEN}7.${PLAIN} Start WARP-Cli"
    echo -e " ${GREEN}8.${PLAIN} Stop WARP-Cli"
    echo -e " ${GREEN}9.${PLAIN} Restart WARP-Cli"
    echo -e " ${GREEN}10.${PLAIN} Start WireProxy-WARP"
    echo -e " ${GREEN}11.${PLAIN} Stop WireProxy-WARP"
    echo -e " ${GREEN}12.${PLAIN} Restart WireProxy-WARP"
    echo ""
    read -rp "Enter option [0-12]: " switch_input
    case $switch_input in
        1)
            systemctl start wg-quick@wgcf >/dev/null 2>&1
            systemctl enable wg-quick@wgcf >/dev/null 2>&1
            ;;
        2)
            wg-quick down wgcf 2>/dev/null
            systemctl stop wg-quick@wgcf >/dev/null 2>&1
            systemctl disable wg-quick@wgcf >/dev/null 2>&1
            ;;
        3)
            wg-quick down wgcf 2>/dev/null
            systemctl stop wg-quick@wgcf >/dev/null 2>&1
            systemctl disable wg-quick@wgcf >/dev/null 2>&1
            systemctl start wg-quick@wgcf >/dev/null 2>&1
            systemctl enable wg-quick@wgcf >/dev/null 2>&1
            ;;
        4)
            systemctl start warp-go
            systemctl enable warp-go >/dev/null 2>&1
            ;;
        5)
            systemctl stop warp-go
            systemctl disable warp-go >/dev/null 2>&1
            ;;
        6)
            systemctl stop warp-go
            systemctl disable warp-go >/dev/null 2>&1
            systemctl start warp-go
            systemctl enable warp-go >/dev/null 2>&1
            ;;
        7)
            warp-cli --accept-tos connect >/dev/null 2>&1
            warp-cli --accept-tos enable-always-on >/dev/null 2>&1
            ;;
        8) warp-cli --accept-tos disconnect >/dev/null 2>&1 ;;
        9)
            warp-cli --accept-tos disconnect >/dev/null 2>&1
            warp-cli --accept-tos connect >/dev/null 2>&1
            warp-cli --accept-tos enable-always-on >/dev/null 2>&1
            ;;
        10)
            systemctl start wireproxy-warp
            systemctl enable wireproxy-warp
            ;;
        11)
            systemctl stop wireproxy-warp
            systemctl disable wireproxy-warp
            ;;
        12)
            systemctl stop wireproxy-warp
            systemctl disable wireproxy-warp
            systemctl start wireproxy-warp
            systemctl enable wireproxy-warp
            ;;
        *) exit 1 ;;
    esac
}

wireguard_profile() {
    yellow "Select WARP client to generate WireGuard config from"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} WARP-GO"
    echo -e " ${GREEN}2.${PLAIN} WGCF"
    echo ""
    read -p "Enter option [1-2]: " profile_mode
    if [[ $profile_mode == 1 ]]; then
        result=$(/opt/warp-go/warp-go --config=/opt/warp-go/warp.conf --export-wireguard=/root/warpgo-proxy.conf) && sleep 5
        if [[ ! $result == "Success" ]]; then
            red "WARP-GO WireGuard config generation failed!"
            exit 1
        fi

        result=$(/opt/warp-go/warp-go --config=/opt/warp-go/warp.conf --export-singbox=/root/warpgo-sing-box.json) && sleep 5
        if [[ ! $result == "Success" ]]; then
            red "WARP-GO Sing-box config generation failed!"
            exit 1
        fi

        green "WARP-GO WireGuard config extracted successfully!"
        yellow "File contents saved to: /root/warpgo-proxy.conf"
        red "$(cat /root/warpgo-proxy.conf)"
        echo ""
        yellow "QR code for node config:"
        qrencode -t ansiutf8 </root/warpgo-proxy.conf
        echo ""
        echo ""
        green "WARP-GO Sing-box config extracted successfully!"
        yellow "File contents saved to: /root/warpgo-sing-box.json"
        red "$(cat /root/warpgo-sing-box.json)"
        yellow "Reserved value: $(grep -o '"reserved":\[[^]]*\]' /root/warpgo-sing-box.json)"
        echo ""
        yellow "Use this method locally to find optimal Endpoint IP: https://blog.misaka.rest/2023/03/12/cf-warp-yxip/"
    elif [[ $profile_mode == 2 ]]; then
        cp -f /etc/wireguard/wgcf-profile.conf /root/wgcf-proxy.conf
        green "WGCF-WARP WireGuard config extracted successfully!"
        yellow "File contents saved to: /root/wgcf-proxy.conf"
        red "$(cat /root/wgcf-proxy.conf)"
        echo ""
        yellow "QR code for node config:"
        qrencode -t ansiutf8 </root/wgcf-proxy.conf
        echo ""
        yellow "Use this method locally to find optimal Endpoint IP: https://blog.misaka.rest/2023/03/12/cf-warp-yxip/"
    else
        red "Invalid input, please try again"
        wireguard_profile
    fi
}

warp_traffic() {
    if [[ -z $(type -P screen) ]]; then
        if [[ ! $SYSTEM == "CentOS" ]]; then
            ${PACKAGE_UPDATE[int]}
        fi
        ${PACKAGE_INSTALL[int]} screen
    fi

    yellow "How to get your CloudFlare WARP account info:"
    green "PC: Download and install CloudFlare WARP → Settings → Preferences → Copy Device ID into script"
    green "Mobile: Download and install 1.1.1.1 APP → Menu → Advanced → Diagnostics → Copy Device ID into script"
    echo ""
    yellow "Please follow instructions below and enter your CloudFlare WARP account info:"
    read -rp "Enter your WARP Device ID (36 characters): " license
    until [[ $license =~ ^[A-F0-9a-f]{8}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{4}-[A-F0-9a-f]{12}$ ]]; do
        red "Invalid Device ID format, please try again!"
        read -rp "Enter your WARP Device ID (36 characters): " license
    done

    wget -N --no-check-certificate https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/wp-plus.py
    sed -i "27 s/[(][^)]*[)]//g" wp-plus.py && sed -i "27 s/input/'$license'/" wp-plus.py

    read -rp "Enter Screen session name (default wp-plus): " screenname
    [[ -z $screenname ]] && screenname="wp-plus"
    screen -UdmS $screenname bash -c '/usr/bin/python3 /root/wp-plus.py'

    green "WARP+ traffic farming task created successfully! Screen session name: $screenname"
}

wgcf_account() {
    yellow "Select WARP account type to switch to"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} WARP Free Account ${YELLOW}(Default)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} WARP+"
    echo -e " ${GREEN}3.${PLAIN} WARP Teams"
    echo ""
    read -p "Enter option [1-3]: " account_type
    if [[ $account_type == 2 ]]; then
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf >/dev/null 2>&1
        
        cd /etc/wireguard

        yellow "How to get CloudFlare WARP license key:"
        green "PC: Download and install CloudFlare WARP → Settings → Preferences → Account → Copy key into script"
        green "Mobile: Download and install 1.1.1.1 APP → Menu → Account → Copy key into script"
        echo ""
        yellow "Important: Make sure your PC or mobile 1.1.1.1 APP account status is WARP+!"
        read -rp "Enter WARP license key (26 characters): " warpkey
        until [[ -z $warpkey || $warpkey =~ ^[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}$ ]]; do
            red "Invalid license key format, please try again!"
            read -rp "Enter WARP license key (26 characters): " warpkey
        done
        sed -i "s/license_key.*/license_key = \"$warpkey\"/g" wgcf-account.toml

        rm -rf /etc/wireguard/wgcf-profile.conf

        read -rp "Enter custom device name (leave empty for random default): " device_name
        if [[ -n $device_name ]]; then
            wgcf update --name $(echo $device_name | sed s/[[:space:]]/_/g) >/etc/wireguard/info.log 2>&1
        else
            wgcf update >/etc/wireguard/info.log 2>&1
        fi

        wgcf generate

        private_v6=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 4p | sed "s/Address = //g")
        private_key=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
        sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/wgcf.conf
        sed -i "s#Address.*128#Address = $private_v6#g" /etc/wireguard/wgcf.conf

        check_wgcf
    elif [[ $account_type == 3 ]]; then
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf >/dev/null 2>&1

        yellow "Select WARP Teams account method"
        echo ""
        echo -e " ${GREEN}1.${PLAIN} Use Teams TOKEN ${YELLOW}(Default)${PLAIN}"
        echo -e " ${GREEN}2.${PLAIN} Use extracted xml config file"
        echo ""
        read -p "Enter option [1-2]: " team_type

        if [[ $team_type == 2 ]]; then
            yellow "How to get WARP Teams xml config: https://blog.misaka.rest/2023/02/11/wgcfteam-config/"
            yellow "Upload extracted xml config to: https://gist.github.com"
            read -rp "Paste WARP Teams config file link: " teamconfigurl
            if [[ -n $teamconfigurl ]]; then
                teams_config=$(curl -sSL "$teamconfigurl" | sed "s/\"/\&quot;/g")
                private_key=$(expr "$teams_config" : '.*private_key&quot;>\([^<]*\).*')
                private_v6=$(expr "$teams_config" : '.*v6&quot;:&quot;\([^[&]*\).*')
                sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/wgcf.conf
                sed -i "s#Address.*128#Address = $private_v6#g" /etc/wireguard/wgcf.conf
                sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/wgcf-profile.conf
                sed -i "s#Address.*128#Address = $private_v6#g" /etc/wireguard/wgcf-profile.conf
                check_wgcf
            else
                red "No WARP Teams config file link provided, exiting!"
                exit 1
            fi
        else
            yellow "Get your WARP Teams TOKEN from: https://web--public--warp-team-api--coia-mfs4.code.run/"
            read -rp "Enter WARP Teams TOKEN: " teams_token

            if [[ -n $teams_token ]]; then
                private_key=$(wg genkey)
                public_key=$(wg pubkey <<< "$private_key")
                install_id=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 22)
                fcm_token="${install_id}:APA91b$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 134)"

                team_result=$(curl --silent --location --tlsv1.3 --request POST 'https://api.cloudflareclient.com/v0a2158/reg' \
                    --header 'User-Agent: okhttp/3.12.1' \
                    --header 'CF-Client-Version: a-6.10-2158' \
                    --header 'Content-Type: application/json' \
                    --header "Cf-Access-Jwt-Assertion: ${teams_token}" \
                    --data '{"key":"'${public_key}'","install_id":"'${install_id}'","fcm_token":"'${fcm_token}'","tos":"'$(date +"%Y-%m-%dT%H:%M:%S.%3NZ")'","model":"Linux","serial_number":"'${install_id}'","locale":"zh_CN"}')

                private_v6=$(expr "$team_result" : '.*"v6":[ ]*"\([^"]*\).*')
                sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/wgcf.conf
                sed -i "s#Address.*128#Address = $private_v6/128#g" /etc/wireguard/wgcf.conf
                sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/wgcf-profile.conf
                sed -i "s#Address.*128#Address = $private_v6/128#g" /etc/wireguard/wgcf-profile.conf
                check_wgcf
            else
                red "No WARP Teams TOKEN entered, exiting!"
                exit 1
            fi
        fi
    else
        wg-quick down wgcf 2>/dev/null
        systemctl stop wg-quick@wgcf >/dev/null 2>&1
        systemctl disable wg-quick@wgcf >/dev/null 2>&1

        rm -f /etc/wireguard/wgcf-account.toml /etc/wireguard/wgcf-profile.conf
        register_wgcf
        mv -f wgcf-profile.conf /etc/wireguard/wgcf-profile.conf
        mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml

        private_v6=$(cat /etc/wireguard/wgcf-profile.conf | sed -n 4p | sed "s/Address = //g")
        private_key=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
        sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/wgcf.conf
        sed -i "s#Address.*128#Address = $private_v6#g" /etc/wireguard/wgcf.conf
        check_wgcf
    fi
}

wpgo_account() {
    check_warp
    if [[ $warp_v4 =~ on|plus ]] || [[ $warp_v6 =~ on|plus ]]; then
        systemctl stop warp-go
        check_stack
        systemctl start warp-go
    else
        check_stack
    fi

    current_allowips=$(cat /opt/warp-go/warp.conf | grep AllowedIPs)
    [[ -n $lan4 && -n $out4 && -z $lan6 && -z $out6 ]] && current_postip=$wgo4
    [[ -z $lan4 && -z $out4 && -n $lan6 && -n $out6 ]] && current_postip=$wgo5
    [[ -n $lan4 && -n $out4 && -n $lan6 && -n $out6 ]] && current_postip=$wgo6
    [[ -n $lan4 && -z $out4 && -n $lan6 && -n $out6 ]] && current_postip=$wgo6

    yellow "Select WARP account type to switch to"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} WARP Free Account ${YELLOW}(Default)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} WARP+"
    echo -e " ${GREEN}3.${PLAIN} WARP Teams"
    echo ""
    read -p "Enter option [1-3]: " account_type

    if [[ $account_type == 2 ]]; then
        systemctl stop warp-go

        yellow "How to get CloudFlare WARP license key:"
        green "PC: Download and install CloudFlare WARP → Settings → Preferences → Account → Copy key into script"
        green "Mobile: Download and install 1.1.1.1 APP → Menu → Account → Copy key into script"
        echo ""
        yellow "Important: Make sure your PC or mobile 1.1.1.1 APP account status is WARP+!"
        read -rp "Enter WARP license key (26 characters): " warpkey
        until [[ -z $warpkey || $warpkey =~ ^[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}$ ]]; do
            red "Invalid license key format, please try again!"
            read -rp "Enter WARP license key (26 characters): " warpkey
        done

        read -rp "Enter custom device name (leave empty for random default): " device_name
        [[ -z $device_name ]] && device_name=$(date +%s%N | md5sum | cut -c 1-6)

        result=$(/opt/warp-go/warp-go --update --config=/opt/warp-go/warp.conf --license=$warpkey --device-name=$devicename)

        if [[ $result == "Success" ]]; then
            sed -i "s#.*AllowedIPs.*#$current_allowips#g" /opt/warp-go/warp.conf
            echo $current_postip | sh
            check_mtu
            sed -i "s/MTU.*/MTU = $MTU/g" /opt/warp-go/warp.conf
            check_endpoint
            sed -i "/Endpoint/s/.*/Endpoint = "$best_endpoint"/" /opt/warp-go/warp.conf
            check_wpgo
        else
            red "WARP+ account registration failed! Reverting to WARP Free account"
            systemctl stop warp-go
            rm -f /opt/warp-go/warp.conf
            register_wpgo
            sed -i "s#.*AllowedIPs.*#$current_allowips#g" /opt/warp-go/warp.conf
            echo $current_postip | sh
            check_mtu
            sed -i "s/MTU.*/MTU = $MTU/g" /opt/warp-go/warp.conf
            check_endpoint
            sed -i "/Endpoint/s/.*/Endpoint = "$best_endpoint"/" /opt/warp-go/warp.conf
            check_wpgo
        fi
    elif [[ $account_type == 3 ]]; then
        systemctl stop warp-go

        yellow "Get your WARP Teams TOKEN from: https://web--public--warp-team-api--coia-mfs4.code.run/"
        read -rp "Enter WARP Teams TOKEN: " teams_token

        if [[ -n $teams_token ]]; then
            read -rp "Enter custom device name (leave empty for random default): " device_name
            [[ -z $device_name ]] && device_name=$(date +%s%N | md5sum | cut -c 1-6)

            /opt/warp-go/warp-go --update --config=/opt/warp-go/warp.conf --team-config=$teams_token --device-name=$device_name
            sed -i "s/Type =.*/Type = team/g" /opt/warp-go/warp.conf
            sed -i "s#.*AllowedIPs.*#$current_allowips#g" /opt/warp-go/warp.conf
            echo $current_postip | sh
            check_mtu
            sed -i "s/MTU.*/MTU = $MTU/g" /opt/warp-go/warp.conf
            check_endpoint
            sed -i "/Endpoint/s/.*/Endpoint = "$best_endpoint"/" /opt/warp-go/warp.conf
            check_wpgo
        else
            red "No WARP Teams TOKEN entered, exiting!"
            exit 1
        fi
    else
        systemctl stop warp-go
        rm -f /opt/warp-go/warp.conf
        register_wpgo
        sed -i "s#.*AllowedIPs.*#${current_allowips}#g" /opt/warp-go/warp.conf
        echo $current_postip | sh
        check_mtu
        sed -i "s/MTU.*/MTU = $MTU/g" /opt/warp-go/warp.conf
        check_endpoint
        sed -i "/Endpoint/s/.*/Endpoint = "$best_endpoint"/" /opt/warp-go/warp.conf
        check_wpgo
    fi
}

warp_cli_account() {
    warp-cli --accept-tos disconnect >/dev/null 2>&1
    warp-cli --accept-tos register >/dev/null 2>&1

    yellow "How to get CloudFlare WARP license key:"
    green "PC: Download and install CloudFlare WARP → Settings → Preferences → Account → Copy key into script"
    green "Mobile: Download and install 1.1.1.1 APP → Menu → Account → Copy key into script"
    echo ""
    yellow "Important: Make sure your PC or mobile 1.1.1.1 APP account status is WARP+!"
    read -rp "Enter WARP license key (26 characters): " warpkey
    until [[ -z $warpkey || $warpkey =~ ^[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}$ ]]; do
        red "Invalid license key format, please try again!"
        read -rp "Enter WARP license key (26 characters): " warpkey
    done

    warp-cli --accept-tos set-license "$warpkey" >/dev/null 2>&1 && sleep 1
    warp-cli --accept-tos connect >/dev/null 2>&1

    if [[ $(warp-cli --accept-tos account) =~ Limited ]]; then
        green "WARP-Cli account switched to WARP+ successfully!"
    else
        red "WARP+ account activation failed, automatically downgraded to WARP Free account"
    fi
}

wireproxy_account() {
    yellow "Select WARP account type to switch to"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} WARP Free Account ${YELLOW}(Default)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} WARP+"
    echo -e " ${GREEN}3.${PLAIN} WARP Teams"
    echo ""
    read -p "Enter option [1-3]: " account_type
    if [[ $account_type == 2 ]]; then
        systemctl stop wireproxy-warp
        systemctl disable wireproxy-warp

        cd /etc/wireguard

        yellow "How to get CloudFlare WARP license key:"
        green "PC: Download and install CloudFlare WARP → Settings → Preferences → Account → Copy key into script"
        green "Mobile: Download and install 1.1.1.1 APP → Menu → Account → Copy key into script"
        echo ""
        yellow "Important: Make sure your PC or mobile 1.1.1.1 APP account status is WARP+!"
        read -rp "Enter WARP license key (26 characters): " warpkey
        until [[ -z $warpkey || $warpkey =~ ^[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}-[A-Z0-9a-z]{8}$ ]]; do
            red "Invalid license key format, please try again!"
            read -rp "Enter WARP license key (26 characters): " warpkey
        done
        sed -i "s/license_key.*/license_key = \"$warpkey\"/g" wgcf-account.toml

        rm -rf /etc/wireguard/wgcf-profile.conf

        read -rp "Enter custom device name (leave empty for random default): " device_name
        if [[ -n $device_name ]]; then
            wgcf update --name $(echo $device_name | sed s/[[:space:]]/_/g) >/etc/wireguard/info.log 2>&1
        else
            wgcf update >/etc/wireguard/info.log 2>&1
        fi

        wgcf generate

        private_key=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
        sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/proxy.conf

        check_wireproxy
    elif [[ $account_type == 3 ]]; then
        systemctl stop wireproxy-warp
        systemctl disable wireproxy-warp

        cd /etc/wireguard

        yellow "Select WARP Teams account method"
        echo ""
        echo -e " ${GREEN}1.${PLAIN} Use Teams TOKEN ${YELLOW}(Default)${PLAIN}"
        echo -e " ${GREEN}2.${PLAIN} Use extracted xml config file"
        echo ""
        read -p "Enter option [1-2]: " team_type

        if [[ $team_type == 2 ]]; then
            yellow "How to get WARP Teams xml config: https://blog.misaka.rest/2023/02/11/wgcfteam-config/"
            yellow "Upload extracted xml config to: https://gist.github.com"
            read -rp "Paste WARP Teams config file link: " teamconfigurl
            if [[ -n $teamconfigurl ]]; then
                teams_config=$(curl -sSL "$teamconfigurl" | sed "s/\"/\&quot;/g")
                private_key=$(expr "$teams_config" : '.*private_key&quot;>\([^<]*\).*')
                private_v6=$(expr "$teams_config" : '.*v6&quot;:&quot;\([^[&]*\).*')
                sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/proxy.conf
                sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/wgcf-profile.conf
                sed -i "s#Address.*128#Address = $private_v6/128#g" /etc/wireguard/wgcf-profile.conf
                check_wireproxy
            else
                red "No WARP Teams config file link provided, exiting!"
            fi
        else
            yellow "Get your WARP Teams TOKEN from: https://web--public--warp-team-api--coia-mfs4.code.run/"
            read -rp "Enter WARP Teams TOKEN: " teams_token

            if [[ -n $teams_token ]]; then
                private_key=$(wg genkey)
                public_key=$(wg pubkey <<< "$private_key")
                install_id=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 22)
                fcm_token="${install_id}:APA91b$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 134)"

                team_result=$(curl --silent --location --tlsv1.3 --request POST 'https://api.cloudflareclient.com/v0a2158/reg' \
                    --header 'User-Agent: okhttp/3.12.1' \
                    --header 'CF-Client-Version: a-6.10-2158' \
                    --header 'Content-Type: application/json' \
                    --header "Cf-Access-Jwt-Assertion: ${teams_token}" \
                    --data '{"key":"'${public_key}'","install_id":"'${install_id}'","fcm_token":"'${fcm_token}'","tos":"'$(date +"%Y-%m-%dT%H:%M:%S.%3NZ")'","model":"Linux","serial_number":"'${install_id}'","locale":"zh_CN"}')

                private_v6=$(expr "$team_result" : '.*"v6":[ ]*"\([^"]*\).*')
                sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/proxy.conf
                sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/wgcf-profile.conf
                sed -i "s#Address.*128#Address = $private_v6/128#g" /etc/wireguard/wgcf-profile.conf
                check_wireproxy
            else
                red "No WARP Teams TOKEN entered, exiting!"
                exit 1
            fi
        fi
    else
        systemctl stop wireproxy-warp
        systemctl disable wireproxy-warp

        rm -f /etc/wireguard/wgcf-account.toml /etc/wireguard/wgcf-profile.conf
        register_wgcf
        mv -f wgcf-profile.conf /etc/wireguard/wgcf-profile.conf
        mv -f wgcf-account.toml /etc/wireguard/wgcf-account.toml

        private_key=$(grep PrivateKey /etc/wireguard/wgcf-profile.conf | sed "s/PrivateKey = //g")
        sed -i "s#PrivateKey.*#PrivateKey = $private_key#g" /etc/wireguard/proxy.conf
        check_wireproxy
    fi
}

warp_account() {
    yellow "Select WARP client to switch account"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} WGCF ${YELLOW}(Default)${PLAIN}"
    echo -e " ${GREEN}2.${PLAIN} WARP-GO"
    echo -e " ${GREEN}3.${PLAIN} WARP-Cli ${RED}(Only supports upgrading to WARP+)${PLAIN}"
    echo -e " ${GREEN}4.${PLAIN} WireProxy"
    echo ""
    read -p "Enter option [1-4]: " account_mode
    if [[ $account_mode == 2 ]]; then
        wpgo_account
    elif [[ $account_mode == 3 ]]; then
        warp_cli_account
    elif [[ $account_mode == 4 ]]; then
        wireproxy_account
    else
        wgcf_account
    fi
}

before_showinfo() {
    yellow "Please wait, detecting VPS, WARP, and unlock status..."

    check_ip
    country4=$(curl -s4m8 ip.p3terx.com | sed -n 2p | awk -F "/ " '{print $2}')
    country6=$(curl -s6m8 ip.p3terx.com | sed -n 2p | awk -F "/ " '{print $2}')
    provider4=$(curl -s4m8 ip.p3terx.com | sed -n 3p | awk -F "/ " '{print $2}')
    provider6=$(curl -s6m8 ip.p3terx.com | sed -n 3p | awk -F "/ " '{print $2}')

    check_warp

    device4="${RED}Not set${PLAIN}"
    device6="${RED}Not set${PLAIN}"

    cli_port=$(warp-cli --accept-tos settings 2>/dev/null | grep 'WarpProxy on port' | awk -F "port " '{print $2}')
    wireproxy_port=$(grep BindAddress /etc/wireguard/proxy.conf 2>/dev/null | sed "s/BindAddress = 127.0.0.1://g")

    if [[ -n $cli_port ]]; then
        account_cli=$(curl -sx socks5h://localhost:$cli_port https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
        country_cli=$(curl -sx socks5h://localhost:$cli_port ip.p3terx.com -k --connect-timeout 8 | sed -n 2p | awk -F "/ " '{print $2}')
        ip_cli=$(curl -sx socks5h://localhost:$cli_port ip.p3terx.com -k --connect-timeout 8 | sed -n 1p)
        provider_cli=$(curl -sx socks5h://localhost:$cli_port ip.p3terx.com -k --connect-timeout 8 | sed -n 3p | awk -F "/ " '{print $2}')
    fi
    if [[ -n $wireproxy_port ]]; then
        account_wireproxy=$(curl -sx socks5h://localhost:$wireproxy_port https://www.cloudflare.com/cdn-cgi/trace -k --connect-timeout 8 | grep warp | cut -d= -f2)
        country_wireproxy=$(curl -sx socks5h://localhost:$wireproxy_port ip.p3terx.com -k --connect-timeout 8 | sed -n 2p | awk -F "/ " '{print $2}')
        ip_wireproxy=$(curl -sx socks5h://localhost:$wireproxy_port ip.p3terx.com -k --connect-timeout 8 | sed -n 1p)
        provider_wireproxy=$(curl -sx socks5h://localhost:$wireproxy_port ip.p3terx.com -k --connect-timeout 8 | sed -n 3p | awk -F "/ " '{print $2}')
    fi

    if [[ $warp_v4 == "plus" ]]; then
        if [[ -n $(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }') ]]; then
            d4=$(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }')
            check_quota
            quota4="${GREEN} $QUOTA ${PLAIN}"
            account4="${GREEN}WARP+${PLAIN}"
        elif [[ $(grep -s "Type" /opt/warp-go/warp.conf | cut -d= -f2 | sed "s# ##g") == "plus" ]]; then
            check_quota
            quota4="${GREEN} $QUOTA ${PLAIN}"
            account4="${GREEN}WARP+${PLAIN}"
        else
            quota4="${RED}Unlimited${PLAIN}"
            account4="${GREEN}WARP Teams${PLAIN}"
        fi
    elif [[ $warp_v4 == "on" ]]; then
        quota4="${RED}Unlimited${PLAIN}"
        account4="${YELLOW}WARP Free Account${PLAIN}"
    else
        quota4="${RED}Unlimited${PLAIN}"
        account4="${RED}WARP Not Enabled${PLAIN}"
    fi

    if [[ $warp_v6 == "plus" ]]; then
        if [[ -n $(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }') ]]; then
            d6=$(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }')
            check_quota
            quota6="${GREEN} $QUOTA ${PLAIN}"
            account6="${GREEN}WARP+${PLAIN}"
        elif [[ $(grep -s "Type" /opt/warp-go/warp.conf | cut -d= -f2 | sed "s# ##g") == "plus" ]]; then
            check_quota
            quota6="${GREEN} $QUOTA ${PLAIN}"
            account6="${GREEN}WARP+${PLAIN}"
        else
            quota6="${RED}Unlimited${PLAIN}"
            account6="${GREEN}WARP Teams${PLAIN}"
        fi
    elif [[ $warp_v6 == "on" ]]; then
        quota6="${RED}Unlimited${PLAIN}"
        account6="${YELLOW}WARP Free Account${PLAIN}"
    else
        quota6="${RED}Unlimited${PLAIN}"
        account6="${RED}WARP Not Enabled${PLAIN}"
    fi

    if [[ $account_cli == "plus" ]]; then
        CHECK_TYPE=1
        check_quota
        quota_cli="${GREEN} $QUOTA ${PLAIN}"
        account_cli="${GREEN}WARP+${PLAIN}"
    elif [[ $account_cli == "on" ]]; then
        quota_cli="${RED}Unlimited${PLAIN}"
        account_cli="${YELLOW}WARP Free Account${PLAIN}"
    else
        quota_cli="${RED}Unlimited${PLAIN}"
        account_cli="${RED}Not Started${PLAIN}"
    fi

    if [[ $account_wireproxy == "plus" ]]; then
        if [[ -n $(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }') ]]; then
            device_wireproxy=$(grep -s 'Device name' /etc/wireguard/info.log | awk '{ print $NF }')
            check_quota
            quota_wireproxy="${GREEN} $QUOTA ${PLAIN}"
            account_wireproxy="${GREEN}WARP+${PLAIN}"
        else
            quota_wireproxy="${RED}Unlimited${PLAIN}"
            account_wireproxy="${GREEN}WARP Teams${PLAIN}"
        fi
    elif [[ $account_wireproxy == "on" ]]; then
        quota_wireproxy="${RED}Unlimited${PLAIN}"
        account_wireproxy="${YELLOW}WARP Free Account${PLAIN}"
    else
        quota_wireproxy="${RED}Unlimited${PLAIN}"
        account_wireproxy="${RED}Not Started${PLAIN}"
    fi

    # Download Netflix detection script if not present
    if [[ ! -f /usr/local/bin/nf ]]; then
        wget https://gitlab.com/Misaka-blog/warp-script/-/raw/main/files/netflix-verify/nf-linux-$(archAffix) -O /usr/local/bin/nf >/dev/null 2>&1
        chmod +x /usr/local/bin/nf
    fi

    netflix4=$(nf | sed -n 3p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    netflix6=$(nf | sed -n 7p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g") && [[ -n $(echo $netflix6 | grep "NF所识别的IP地域信息") ]] && netflix6=$(nf | sed -n 6p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    [[ -n $cli_port ]] && netflix_cli=$(nf -proxy socks5://127.0.0.1:$cli_port | sed -n 3p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")
    [[ -n $wireproxy_port ]] && netflix_wireproxy=$(nf -proxy socks5://127.0.0.1:$wireproxy_port | sed -n 3p | sed -r "s/\x1B\[([0-9]{1,2}(;[0-9]{1,2})?)?[m|K]//g")

    # Simplify Netflix detection output
    [[ $netflix4 == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]] && netflix4="${GREEN}Netflix Unlocked${PLAIN}"
    [[ $netflix6 == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]] && netflix6="${GREEN}Netflix Unlocked${PLAIN}"
    [[ $netflix4 == "您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]] && netflix4="${YELLOW}Netflix Originals Only${PLAIN}"
    [[ $netflix6 == "您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]] && netflix6="${YELLOW}Netflix Originals Only${PLAIN}"
    [[ -z $netflix4 ]] || [[ $netflix4 == "您的网络可能没有正常配置IPv4，或者没有IPv4网络接入" ]] && netflix4="${RED}Cannot detect Netflix status${PLAIN}"
    [[ -z $netflix6 ]] || [[ $netflix6 == "您的网络可能没有正常配置IPv6，或者没有IPv6网络接入" ]] && netflix6="${RED}Cannot detect Netflix status${PLAIN}"
    [[ $netflix4 =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务" ]] && netflix4="${RED}Netflix Not Unlocked${PLAIN}"
    [[ $netflix6 =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务" ]] && netflix6="${RED}Netflix Not Unlocked${PLAIN}"
    [[ $netflix_cli == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]] && netflix_cli="${GREEN}Netflix Unlocked${PLAIN}"
    [[ $netflix_wireproxy == "您的出口IP完整解锁Netflix，支持非自制剧的观看" ]] && netflix_wireproxy="${GREEN}Netflix Unlocked${PLAIN}"
    [[ $netflix_cli == "您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]] && netflix_cli="${YELLOW}Netflix Originals Only${PLAIN}"
    [[ $netflix_wireproxy == "您的出口IP可以使用Netflix，但仅可看Netflix自制剧" ]] && netflix_wireproxy="${YELLOW}Netflix Originals Only${PLAIN}"
    [[ $netflix_cli =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务" ]] && netflix_cli="${RED}Netflix Not Unlocked${PLAIN}"
    [[ $netflix_wireproxy =~ "Netflix在您的出口IP所在的国家不提供服务"|"Netflix在您的出口IP所在的国家提供服务，但是您的IP疑似代理，无法正常使用服务" ]] && netflix_wireproxy="${RED}Netflix Not Unlocked${PLAIN}"

    # Test ChatGPT unlock status
    curl -s4m8 https://chat.openai.com/ | grep -qw "Sorry, you have been blocked" && chatgpt4="${RED}ChatGPT Blocked${PLAIN}" || chatgpt4="${GREEN}ChatGPT Supported${PLAIN}"
    curl -s6m8 https://chat.openai.com/ | grep -qw "Sorry, you have been blocked" && chatgpt6="${RED}ChatGPT Blocked${PLAIN}" || chatgpt6="${GREEN}ChatGPT Supported${PLAIN}"
    if [[ -n $cli_port ]]; then
        curl -sx socks5h://localhost:$cli_port https://chat.openai.com/ | grep -qw "Sorry, you have been blocked" && chatgpt_cli="${RED}ChatGPT Blocked${PLAIN}" || chatgpt_cli="${GREEN}ChatGPT Supported${PLAIN}"
    fi
    if [[ -n $wireproxy_port ]]; then
        curl -sx socks5h://localhost:$wireproxy_port https://chat.openai.com/ | grep -qw "Sorry, you have been blocked" && chatgpt_wireproxy="${RED}ChatGPT Blocked${PLAIN}" || chatgpt_wireproxy="${GREEN}ChatGPT Supported${PLAIN}"
    fi
}

show_info() {
    echo "----------------------------------------------------------------------------"
    if [[ -n $ipv4 ]]; then
        echo -e "IPv4 Address: $ipv4  Country: $country4  Device Name: $device4"
        echo -e "Provider: $provider4  WARP Account Status: $account4  Remaining Traffic: $quota4"
        echo -e "Netflix Status: $netflix4  ChatGPT Status: $chatgpt4"
    else
        echo -e "IPv4 Outbound Status: ${RED}Not Enabled${PLAIN}"
    fi
    echo "----------------------------------------------------------------------------"
    if [[ -n $ipv6 ]]; then
        echo -e "IPv6 Address: $ipv6  Country: $country6  Device Name: $device6"
        echo -e "Provider: $provider6  WARP Account Status: $account6  Remaining Traffic: $quota6"
        echo -e "Netflix Status: $netflix6  ChatGPT Status: $chatgpt6"
    else
        echo -e "IPv6 Outbound Status: ${RED}Not Enabled${PLAIN}"
    fi
    echo "----------------------------------------------------------------------------"
    if [[ -n $cli_port ]]; then
        echo -e "WARP-Cli Proxy Port: 127.0.0.1:$cli_port  Status: $account_cli  Remaining Traffic: $quota_cli"
        if [[ -n $ip_cli ]]; then
            echo -e "IP: $ip_cli  Country: $country_cli  Provider: $provider_cli"
            echo -e "Netflix Status: $netflix_cli  ChatGPT Status: $chatgpt_cli"
        fi
    else
        echo -e "WARP-Cli Outbound Status: ${RED}Not Installed${PLAIN}"
    fi
    echo "----------------------------------------------------------------------------"
    if [[ -n $wireproxy_port ]]; then
        echo -e "WireProxy-WARP Proxy Port: 127.0.0.1:$wireproxy_port  Status: $account_wireproxy  Remaining Traffic: $quota_wireproxy"
        if [[ -n $ip_wireproxy ]]; then
            echo -e "IP: $ip_wireproxy  Country: $country_wireproxy  Provider: $provider_wireproxy"
            echo -e "Netflix Status: $netflix_wireproxy  ChatGPT Status: $chatgpt_wireproxy"
        fi
    else
        echo -e "WireProxy Outbound Status: ${RED}Not Installed${PLAIN}"
    fi
    echo "----------------------------------------------------------------------------"
}

menu() {
    clear
    echo "#############################################################"
    echo -e "#            ${RED}CloudFlare WARP Management Script${PLAIN}                #"
    echo -e "# ${GREEN}Author${PLAIN}: 404 \ 2.0                                        #"
    echo -e "# ${GREEN}GitHub Project${PLAIN}: https://github.com/nyeinkokoaung404               #"
    echo -e "# ${GREEN}Telegram Channel${PLAIN}: https://t.me/premium_channel_404              #"
    echo -e "# ${GREEN}Telegram Group${PLAIN}: https://t.me/premium_channel_404_chat                     #"
    echo "#############################################################"
    echo ""
    echo -e " ${GREEN}1.${PLAIN} Install / Switch WGCF-WARP          | ${GREEN}3.${PLAIN} Install / Switch WARP-GO"
    echo -e " ${GREEN}2.${PLAIN} ${RED}Uninstall WGCF-WARP${PLAIN}                 | ${GREEN}4.${PLAIN} ${RED}Uninstall WARP-GO${PLAIN}"
    echo " -------------------------------------------------------------"
    echo -e " ${GREEN}5.${PLAIN} Install WARP-Cli                  | ${GREEN}7.${PLAIN} Install WireProxy-WARP"
    echo -e " ${GREEN}6.${PLAIN} ${RED}Uninstall WARP-Cli${PLAIN}                  | ${GREEN}8.${PLAIN} ${RED}Uninstall WireProxy-WARP${PLAIN}"
    echo " -------------------------------------------------------------"
    echo -e " ${GREEN}9.${PLAIN} Modify WARP-Cli / WireProxy Port | ${GREEN}10.${PLAIN} Start, Stop, or Restart WARP"
    echo -e " ${GREEN}11.${PLAIN} Extract WireGuard Config         | ${GREEN}12.${PLAIN} WARP+ Traffic Farming"
    echo -e " ${GREEN}13.${PLAIN} Switch WARP Account Type         | ${GREEN}14.${PLAIN} Pull Latest Script from GitLab"
    echo " -------------------------------------------------------------"
    echo -e " ${GREEN}0.${PLAIN} Exit Script"
    echo ""
    show_info
    echo ""
    read -rp "Enter option [0-14]: " menu_input
    
    case $menu_input in
        1) select_wgcf ;;
        2) uninstall_wgcf ;;
        3) select_wpgo ;;
        4) uninstall_wpgo ;;
        5) install_warp_cli ;;
        6) uninstall_warp_cli ;;
        7) install_wireproxy ;;
        8) uninstall_wireproxy ;;
        9) change_warp_port ;;
        10) switch_warp ;;
        11) wireguard_profile ;;
        12) warp_traffic ;;
        13) warp_account ;;
        14) wget -N https://gitlab.com/nyeinkokoaung404/warp-script/-/raw/main/warp.sh && bash warp.sh ;;
        *) exit 1 ;;
    esac
}

before_showinfo && menu
