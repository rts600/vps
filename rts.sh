#!/bin/bash

sh_v="VPS定制脚本"

huang='\033[33m'
bai='\033[0m'
lv='\033[0;32m'
lan='\033[0;34m'
hong='\033[31m'
kjlan='\033[96m'
hui='\e[37m'

cp ./rts.sh /usr/local/bin/v > /dev/null 2>&1

ip_address() {
ipv4_address=$(curl -s ipv4.ip.sb)
ipv6_address=$(curl -s --max-time 1 ipv6.ip.sb)
}


install() {
    if [ $# -eq 0 ]; then
        echo "未提供软件包参数!"
        return 1
    fi

    for package in "$@"; do
        if ! command -v "$package" &>/dev/null; then
            if command -v dnf &>/dev/null; then
                dnf -y update && dnf install -y "$package"
            elif command -v yum &>/dev/null; then
                yum -y update && yum -y install "$package"
            elif command -v apt &>/dev/null; then
                apt update -y && apt install -y "$package"
            elif command -v apk &>/dev/null; then
                apk update && apk add "$package"
            else
                echo "未知的包管理器!"
                return 1
            fi
        fi
    done

    return 0
}

uninstall() {
    rm -rf rts.sh
    rm -rf /usr/local/bin/v
    rm -rf Internet_Limit.sh
}

remove() {
    if [ $# -eq 0 ]; then
        echo "未提供软件包参数!"
        return 1
    fi

    for package in "$@"; do
        if command -v dnf &>/dev/null; then
            dnf remove -y "${package}*"
        elif command -v yum &>/dev/null; then
            yum remove -y "${package}*"
        elif command -v apt &>/dev/null; then
            apt purge -y "${package}*"
        elif command -v apk &>/dev/null; then
            apk del "${package}*"
        else
            echo "未知的包管理器!"
            return 1
        fi
    done

    return 0
}


break_end() {
      echo -e "${lv}操作完成${bai}"
      echo "按任意键继续..."
      read -n 1 -s -r -p ""
      echo ""
      clear
}


rts() {
            v
            exit
}


check_port() {
    # 定义要检测的端口
    PORT=443

    # 检查端口占用情况
    result=$(ss -tulpn | grep ":$PORT")

    # 判断结果并输出相应信息
    if [ -n "$result" ]; then
        is_nginx_container=$(docker ps --format '{{.Names}}' | grep 'nginx')

        # 判断是否是Nginx容器占用端口
        if [ -n "$is_nginx_container" ]; then
            echo ""
        else
            clear
            echo -e "${hong}端口 ${huang}$PORT${hong} 已被占用，无法安装环境，卸载以下程序后重试！${bai}"
            echo "$result"
            break_end
            rts

        fi
    else
        echo ""
    fi
}


restart_ssh() {

if command -v dnf &>/dev/null; then
    systemctl restart sshd
elif command -v yum &>/dev/null; then
    systemctl restart sshd
elif command -v apt &>/dev/null; then
    service ssh restart
elif command -v apk &>/dev/null; then
    service sshd restart
else
    echo "未知的包管理器!"
    return 1
fi

}


linux_update() {

    # Update system on Debian-based systems
    if [ -f "/etc/debian_version" ]; then
        apt update -y && DEBIAN_FRONTEND=noninteractive apt full-upgrade -y
    fi

    # Update system on Red Hat-based systems
    if [ -f "/etc/redhat-release" ]; then
        yum -y update
    fi

}


linux_clean() {
    clean_debian() {
        apt autoremove --purge -y
        apt clean -y
        apt autoclean -y
        apt remove --purge $(dpkg -l | awk '/^rc/ {print $2}') -y
        journalctl --rotate
        journalctl --vacuum-time=1s
        journalctl --vacuum-size=50M
        apt remove --purge $(dpkg -l | awk '/^ii linux-(image|headers)-[^ ]+/{print $2}' | grep -v $(uname -r | sed 's/-.*//') | xargs) -y
    }

    clean_redhat() {
        yum autoremove -y
        yum clean all
        journalctl --rotate
        journalctl --vacuum-time=1s
        journalctl --vacuum-size=50M
        yum remove $(rpm -q kernel | grep -v $(uname -r)) -y
    }

    # Main script
    if [ -f "/etc/debian_version" ]; then
        # Debian-based systems
        clean_debian
    elif [ -f "/etc/redhat-release" ]; then
        # Red Hat-based systems
        clean_redhat
    fi

}

bbr_on() {

echo "net.core.default_qdisc=fq_pie" >> /etc/sysctl.conf > /dev/null 2>&1
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf > /dev/null 2>&1
sysctl -p > /dev/null 2>&1

}

install_add_docker() {
    if [ -f "/etc/alpine-release" ]; then
        apk update
        apk add docker docker-compose
        rc-update add docker default
        service docker start
    else
        curl -fsSL https://get.docker.com | sh && ln -s /usr/libexec/docker/cli-plugins/docker-compose /usr/local/bin
        systemctl start docker
        systemctl enable docker
    fi

    sleep 2
}


install_docker() {
    if ! command -v docker &>/dev/null || ! command -v docker-compose &>/dev/null; then
        install_add_docker
    else
        echo "Docker环境已经安装"
    fi
}


iptables_open() {
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F
    rm -rf /etc/iptables    
}


add_swap() {
    # 获取当前系统中所有的 swap 分区
    swap_partitions=$(grep -E '^/dev/' /proc/swaps | awk '{print $1}')

    # 遍历并删除所有的 swap 分区
    for partition in $swap_partitions; do
      swapoff "$partition"
      wipefs -a "$partition"  # 清除文件系统标识符
      mkswap -f "$partition"
    done

    # 确保 /swapfile 不再被使用
    swapoff /swapfile

    # 删除旧的 /swapfile
    rm -f /swapfile

    # 创建新的 swap 分区
    dd if=/dev/zero of=/swapfile bs=1M count=$new_swap
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile

    if [ -f /etc/alpine-release ]; then
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
        echo "nohup swapon /swapfile" >> /etc/local.d/swap.start
        chmod +x /etc/local.d/swap.start
        rc-update add local
    else
        echo "/swapfile swap swap defaults 0 0" >> /etc/fstab
    fi

    echo -e "虚拟内存大小已调整为${huang}${new_swap}${bai}MB"
}


docker_app() {
if docker inspect "$docker_name" &>/dev/null; then
    clear
    echo "$docker_name 已安装，访问地址: "
    ip_address
    echo "http:$ipv4_address:$docker_port"
    echo ""
    echo "应用操作"
    echo "------------------------"
    echo "1. 更新应用"
    echo "2. 卸载应用"
    echo "------------------------"
    echo "e. 返回上一级选单"
    echo "------------------------"
    read -p "请输入你的选择: " sub_choice

    case $sub_choice in
        1)
            clear
            docker rm -f "$docker_name"
            docker rmi -f "$docker_img"

            $docker_rum
            clear
            echo "$docker_name 已经安装完成"
            echo "------------------------"
            # 获取外部 IP 地址
            ip_address
            echo "您可以使用以下地址访问:"
            echo "http:$ipv4_address:$docker_port"
            $docker_use
            $docker_passwd
            ;;
        2)
            clear
            docker rm -f "$docker_name"
            docker rmi -f "$docker_img"
            rm -rf "/home/docker/$docker_name"
            echo "应用已卸载"
            ;;
        e)
            # 跳出循环，退出菜单
            ;;
        *)
            # 跳出循环，退出菜单
            ;;
    esac
else
    clear
    echo "安装提示"
    echo "$docker_describe"
    echo "$docker_url"
    echo ""

    # 提示用户确认安装
    read -p "确定安装吗？(Y/N): " choice
    case "$choice" in
        [Yy])
            clear
            # 安装 Docker（请确保有 install_docker 函数）
            install_docker
            $docker_rum
            clear
            echo "$docker_name 已经安装完成"
            echo "------------------------"
            # 获取外部 IP 地址
            ip_address
            echo "您可以使用以下地址访问:"
            echo "http:$ipv4_address:$docker_port"
            $docker_use
            $docker_passwd
            ;;
        [Nn])
            # 用户选择不安装
            ;;
        *)
            # 无效输入
            ;;
    esac
fi

}


server_reboot() {

    read -p "$(echo -e "现在${huang}重启服务器${bai}吗？(Y/N): ")" rboot
    case "$rboot" in
      [Yy])
        echo "已重启"
        reboot
        ;;
      [Nn])
        echo "已取消"
        ;;
      *)
        echo "无效的选择，请输入 Y 或 N。"
        ;;
    esac

}


output_status() {
    output=$(awk 'BEGIN { rx_total = 0; tx_total = 0 }
        NR > 2 { rx_total += $2; tx_total += $10 }
        END {
            rx_units = "Bytes";
            tx_units = "Bytes";
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "KB"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "MB"; }
            if (rx_total > 1024) { rx_total /= 1024; rx_units = "GB"; }

            if (tx_total > 1024) { tx_total /= 1024; tx_units = "KB"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "MB"; }
            if (tx_total > 1024) { tx_total /= 1024; tx_units = "GB"; }

            printf("总接收: %.2f %s\n总发送: %.2f %s\n", rx_total, rx_units, tx_total, tx_units);
        }' /proc/net/dev)

}


install_panel() {
            if $lujing ; then
                clear
                echo "$panelname 已安装，应用操作"
                echo ""
                echo "------------------------"
                echo "1. 管理$panelname"
                echo "2. 卸载$panelname"                
                echo "------------------------"
                echo "e. 返回上一级选单"
                echo "------------------------"
                read -p "请输入你的选择: " sub_choice

                case $sub_choice in
                    1)
                        clear
                        $gongneng1
                        $gongneng1_1
                        ;;
                    2)
                        clear
                        $gongneng2
                        $gongneng2_1
                        $gongneng2_2
                        ;;
                    e)
                        break  # 跳出循环，退出菜单
                        ;;
                    *)
                        break  # 跳出循环，退出菜单
                        ;;
                esac
            else
                clear
                echo "安装提示"
                echo "如果您已经安装了其他面板工具或者LDNMP建站环境，先卸载再安装$panelname！"
                echo "会根据系统自动安装，支持Debian，Ubuntu"
                echo "官网介绍: $panelurl "
                echo ""

                read -p "确定安装 $panelname 吗？(Y/N): " choice
                case "$choice" in
                    [Yy])
                        iptables_open
                        install wget
                        if grep -qi 'Ubuntu' /etc/os-release; then
                            $ubuntu_mingling
                            $ubuntu_mingling2
                        elif grep -qi 'Debian' /etc/os-release; then
                            $ubuntu_mingling
                            $ubuntu_mingling2
                        else
                            echo "Unsupported OS"
                        fi
                                                    ;;
                    [Nn])
                        ;;
                    *)
                        ;;
                esac

            fi

}


while true; do
clear

echo -e "${kjlan}_  _ ____  _ _ _    _ ____ _  _ "
echo -e "${kjlan}$sh_v[支持Ubuntu/Debian系统]${bai}"
echo -e "${kjlan}-输入${hong}v${kjlan}快速启动定制脚本-${bai}"
echo "------------------------"
echo "a. 新机设置 ▶"
echo "1. 系统信息"
echo "2. 系统更新"
echo "3. 系统清理"
echo "4. 系统工具 ▶"
echo "5. 测试工具 ▶"
echo "6. 常用工具 ▶"
echo "7. 面板工具 ▶"
echo "8. Docker管理 ▶"
echo "------------------------"
echo "e. 退出脚本"
echo "i. 卸载脚本"
echo "------------------------"
read -p "请输入你的选择: " choice

case $choice in
  a)
      echo "新机系统设置"
      echo "------------------------------------------------"
      echo "以下内容将进行设置与调整"
      echo "1. 更新系统"
      echo "2. 清理系统"
      echo -e "3. 设置时区到${huang}上海${bai}"
      echo -e "4. 开放所有IPV4端口"
      echo -e "5. 开启${huang}BBR${bai}加速"
      echo "------------------------------------------------"
      read -p "确定进行设置与调整吗？(Y/N): " choice

      case "$choice" in
      [Yy])
      clear

      echo "------------------------------------------------"
      linux_update
      echo -e "[${lv}OK${bai}] 1/5. 更新系统到最新"

      echo "------------------------------------------------"
      linux_clean
      echo -e "[${lv}OK${bai}] 2/5. 清理系统垃圾文件"

      echo "------------------------------------------------"
      timedatectl set-timezone Asia/Shanghai
      echo -e "[${lv}OK${bai}] 3/5. 设置时区到${huang}上海${bai}"

      echo "------------------------------------------------"
      iptables_open
      echo -e "[${lv}OK${bai}] 4/5. 开放所有IPV4端口"

      echo "------------------------------------------------"
      bbr_on
      echo -e "[${lv}OK${bai}] 5/5. 开启${huang}BBR${bai}加速"

      echo "------------------------------------------------"
      echo -e "${lv}系统设置已完成，重启中...${bai}"
      reboot
       ;;
      [Nn])
      echo "已取消"
       ;;
      *)
      echo "无效的选择，请输入 Y 或 N。"
       ;;
       esac
       ;;  
       
  1)
    clear
    # 函数: 获取IPv4和IPv6地址
    ip_address

    if [ "$(uname -m)" == "x86_64" ]; then
      cpu_info=$(cat /proc/cpuinfo | grep 'model name' | uniq | sed -e 's/model name[[:space:]]*: //')
    else
      cpu_info=$(lscpu | grep 'BIOS Model name' | awk -F': ' '{print $2}' | sed 's/^[ \t]*//')
    fi

    if [ -f /etc/alpine-release ]; then
        # Alpine Linux 使用以下命令获取 CPU 使用率
        cpu_usage_percent=$(top -bn1 | grep '^CPU' | awk '{print " "$4}' | cut -c 1-2)
    else
        # 其他系统使用以下命令获取 CPU 使用率
        cpu_usage_percent=$(top -bn1 | grep "Cpu(s)" | awk '{print " "$2}')
    fi

    cpu_cores=$(nproc)

    mem_info=$(free -b | awk 'NR==2{printf "%.2f/%.2f MB (%.2f%%)", $3/1024/1024, $2/1024/1024, $3*100/$2}')

    disk_info=$(df -h | awk '$NF=="/"{printf "%s/%s (%s)", $3, $2, $5}')

    country=$(curl -s ipinfo.io/country)
    city=$(curl -s ipinfo.io/city)

    isp_info=$(curl -s ipinfo.io/org)

    cpu_arch=$(uname -m)

    hostname=$(hostname)

    kernel_version=$(uname -r)

    congestion_algorithm=$(sysctl -n net.ipv4.tcp_congestion_control)
    queue_algorithm=$(sysctl -n net.core.default_qdisc)

    # 尝试使用 lsb_release 获取系统信息
    os_info=$(lsb_release -ds 2>/dev/null)

    # 如果 lsb_release 命令失败，则尝试其他方法
    if [ -z "$os_info" ]; then
      # 检查常见的发行文件
      if [ -f "/etc/os-release" ]; then
        os_info=$(source /etc/os-release && echo "$PRETTY_NAME")
      elif [ -f "/etc/debian_version" ]; then
        os_info="Debian $(cat /etc/debian_version)"
      elif [ -f "/etc/redhat-release" ]; then
        os_info=$(cat /etc/redhat-release)
      else
        os_info="Unknown"
      fi
    fi

    output_status

    current_time=$(date "+%Y-%m-%d %I:%M %p")

    swap_used=$(free -m | awk 'NR==3{print $3}')
    swap_total=$(free -m | awk 'NR==3{print $2}')

    if [ "$swap_total" -eq 0 ]; then
        swap_percentage=0
    else
        swap_percentage=$((swap_used * 100 / swap_total))
    fi

    swap_info="${swap_used}MB/${swap_total}MB (${swap_percentage}%)"

    runtime=$(cat /proc/uptime | awk -F. '{run_days=int($1 / 86400);run_hours=int(($1 % 86400) / 3600);run_minutes=int(($1 % 3600) / 60); if (run_days > 0) printf("%d天 ", run_days); if (run_hours > 0) printf("%d时 ", run_hours); printf("%d分\n", run_minutes)}')

    echo ""
    echo "系统信息"
    echo "------------------------"
    echo "主机名: $hostname"
    echo "运营商: $isp_info"
    echo "------------------------"
    echo "系统版本: $os_info"
    echo "Linux版本: $kernel_version"
    echo "------------------------"
    echo "CPU架构: $cpu_arch"
    echo "CPU型号: $cpu_info"
    echo "CPU核心数: $cpu_cores"
    echo "------------------------"
    echo "CPU占用: $cpu_usage_percent%"
    echo "物理内存: $mem_info"
    echo "虚拟内存: $swap_info"
    echo "硬盘占用: $disk_info"
    echo "------------------------"
    echo "$output"
    echo "------------------------"
    echo "网络拥堵算法: $congestion_algorithm $queue_algorithm"
    echo "------------------------"
    echo "公网IPv4地址: $ipv4_address"
    echo "公网IPv6地址: $ipv6_address"
    echo "------------------------"
    echo "地理位置: $country $city"
    echo "系统时间: $current_time"
    echo "------------------------"
    echo "系统运行时长: $runtime"
    echo

    ;;

  2)
    clear
    linux_update
    ;;

  3)
    clear
    ;;

  4)
    while true; do
      clear
      echo "▶ 系统工具"
      echo "------------------------"
      echo "1. 系统时区调整"
      echo "2. 开放IPV4端口"
      echo "3. ROOT密码登录"
      echo "4. 限流自动关机"
      echo "5. DD重装系统"      
      echo "6. 一键重装系统"
      echo "7. 修改主机名"     
      echo "8. 用户管理"            
      echo "9. 定时任务管理"      
      echo "a. 更改脚本快捷键"
      echo "b. 查看端口状态"
      echo "c. 甲骨文工具"      
      echo "------------------------"      
      echo "r. 重启服务器"
      echo "------------------------"
      echo "e. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          a)
              clear
              read -p "请输入你的快捷按键: " kuaijiejian
              echo "alias $kuaijiejian='~/rts.sh'" >> ~/.bashrc
              source ~/.bashrc
              echo "快捷键已设置"
              ;;             
          b)
            clear
            ss -tulnape
            ;;
          2)
              clear
              iptables_open
              echo "IPV4端口已开放"
              ;;
          1)
            while true; do
                clear
                echo "系统时间信息"

                # 获取当前系统时区
                current_timezone=$(timedatectl show --property=Timezone --value)

                # 获取当前系统时间
                current_time=$(date +"%Y-%m-%d %H:%M:%S")

                # 显示时区和时间
                echo "当前系统时区：$current_timezone"
                echo "当前系统时间：$current_time"

                echo ""
                echo "时区切换"
                echo "亚洲------------------------"
                echo "1. 中国上海时间              2. 中国香港时间"
                echo "3. 日本东京时间              4. 韩国首尔时间"
                echo "5. 新加坡时间                6. 印度加尔各答时间"
                echo "7. 阿联酋迪拜时间            8. 澳大利亚悉尼时间"
                echo "欧洲------------------------"
                echo "11. 英国伦敦时间             12. 法国巴黎时间"
                echo "13. 德国柏林时间             14. 俄罗斯莫斯科时间"
                echo "15. 荷兰尤特赖赫特时间        16. 西班牙马德里时间"
                echo "美洲------------------------"
                echo "21. 美国西部时间              22. 美国东部时间"
                echo "23. 加拿大时间               24. 墨西哥时间"
                echo "25. 巴西时间                 26. 阿根廷时间"
                echo "------------------------"
                echo "e. 返回上一级选单"
                echo "------------------------"
                read -p "请输入你的选择: " sub_choice

                case $sub_choice in
                    1) timedatectl set-timezone Asia/Shanghai ;;
                    2) timedatectl set-timezone Asia/Hong_Kong ;;
                    3) timedatectl set-timezone Asia/Tokyo ;;
                    4) timedatectl set-timezone Asia/Seoul ;;
                    5) timedatectl set-timezone Asia/Singapore ;;
                    6) timedatectl set-timezone Asia/Kolkata ;;
                    7) timedatectl set-timezone Asia/Dubai ;;
                    8) timedatectl set-timezone Australia/Sydney ;;
                    11) timedatectl set-timezone Europe/London ;;
                    12) timedatectl set-timezone Europe/Paris ;;
                    13) timedatectl set-timezone Europe/Berlin ;;
                    14) timedatectl set-timezone Europe/Moscow ;;
                    15) timedatectl set-timezone Europe/Amsterdam ;;
                    16) timedatectl set-timezone Europe/Madrid ;;
                    21) timedatectl set-timezone America/Los_Angeles ;;
                    22) timedatectl set-timezone America/New_York ;;
                    23) timedatectl set-timezone America/Vancouver ;;
                    24) timedatectl set-timezone America/Mexico_City ;;
                    25) timedatectl set-timezone America/Sao_Paulo ;;
                    26) timedatectl set-timezone America/Argentina/Buenos_Aires ;;
                    e) break ;; # 跳出循环，退出菜单
                    *) break ;; # 跳出循环，退出菜单
                esac
            done
              ;;
          4)
            clear
            echo "当前流量使用情况，重启服务器流量计算会清零！"
            output_status
            echo "$output"

            # 检查是否存在 Internet_Limit.sh 文件
            if [ -f ~/Internet_Limit.sh ]; then
                # 获取 threshold_gb 的值
                threshold_gb=$(grep -oP 'threshold_gb=\K\d+' ~/Internet_Limit.sh)
                echo -e "当前设置的限流阈值为 ${hang}${threshold_gb}${bai}GB"
            else
                echo -e "${hui}前未启用限流关机功能${bai}"
            fi

            echo
            echo "------------------------------------------------"
            echo "系统每分钟检测实际流量是否到达阈值，到达后会自动关闭服务器！每月1日重置流量重启服务器。"
            read -p "1. 开启限流关机功能    2. 停用限流关机功能    e. 退出  : " Limit

            case "$Limit" in
              1)
                # 输入新的虚拟内存大小
                echo "如果实际服务器就100G流量，可设置阈值为95G，提前关机，以免出现流量误差或溢出."
                read -p "请输入流量阈值（单位为GB）: " threshold_gb
                cd ~
                curl -Ss -O https://raw.githubusercontent.com/rts600/vps/main/Internet_Limit.sh
                chmod +x ~/Internet_Limit.sh
                sed -i "s/110/$threshold_gb/g" ~/Internet_Limit.sh
                crontab -l | grep -v '~/Internet_Limit.sh' | crontab -
                (crontab -l ; echo "* * * * * ~/Internet_Limit.sh") | crontab - > /dev/null 2>&1
                crontab -l | grep -v 'reboot' | crontab -
                (crontab -l ; echo "0 1 1 * * reboot") | crontab - > /dev/null 2>&1
                echo "限流关机已设置"
                ;;
              e)
                echo "已取消"
                ;;
              2)
                crontab -l | grep -v '~/Internet_Limit.sh' | crontab -
                crontab -l | grep -v 'reboot' | crontab -
                rm ~/Internet_Limit.sh
                echo "已关闭限流关机功能"
                ;;
              *)
                echo "无效的选择，请输入 Y 或 N。"
                ;;
            esac
              ;;

          8)
              while true; do
                clear
                install sudo
                clear
                # 显示所有用户、用户权限、用户组和是否在sudoers中
                echo "用户列表"
                echo "----------------------------------------------------------------------------"
                printf "%-24s %-34s %-20s %-10s\n" "用户名" "用户权限" "用户组" "sudo权限"
                while IFS=: read -r username _ userid groupid _ _ homedir shell; do
                    groups=$(groups "$username" | cut -d : -f 2)
                    sudo_status=$(sudo -n -lU "$username" 2>/dev/null | grep -q '(ALL : ALL)' && echo "Yes" || echo "No")
                    printf "%-20s %-30s %-20s %-10s\n" "$username" "$homedir" "$groups" "$sudo_status"
                done < /etc/passwd

                  echo ""
                  echo "账户操作"
                  echo "------------------------"
                  echo "1. 创建普通账户             2. 创建高级账户"
                  echo "------------------------"
                  echo "3. 赋予最高权限             4. 取消最高权限"
                  echo "------------------------"
                  echo "5. 删除账号"
                  echo "------------------------"
                  echo "e. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                       # 提示用户输入新用户名
                       read -p "请输入新用户名: " new_username

                       # 创建新用户并设置密码
                       sudo useradd -m -s /bin/bash "$new_username"
                       sudo passwd "$new_username"

                       echo "操作已完成。"
                          ;;
                      2)
                       # 提示用户输入新用户名
                       read -p "请输入新用户名: " new_username

                       # 创建新用户并设置密码
                       sudo useradd -m -s /bin/bash "$new_username"
                       sudo passwd "$new_username"

                       # 赋予新用户sudo权限
                       echo "$new_username ALL=(ALL:ALL) ALL" | sudo tee -a /etc/sudoers

                       echo "操作已完成。"
                          ;;
                      3)
                       read -p "请输入用户名: " username
                       # 赋予新用户sudo权限
                       echo "$username ALL=(ALL:ALL) ALL" | sudo tee -a /etc/sudoers
                          ;;
                      4)
                       read -p "请输入用户名: " username
                       # 从sudoers文件中移除用户的sudo权限
                       sudo sed -i "/^$username\sALL=(ALL:ALL)\sALL/d" /etc/sudoers
                          ;;
                      5)
                       read -p "请输入要删除的用户名: " username
                       # 删除用户及其主目录
                       sudo userdel -r "$username"
                          ;;
                      e)
                          break  # 跳出循环，退出菜单
                          ;;
                      *)
                          break  # 跳出循环，退出菜单
                          ;;
                  esac
              done
              ;;
          5)
          clear
          echo "请备份数据，将为你重装系统，预计花费15分钟。"
          read -p "确定继续吗？(Y/N): " choice

          case "$choice" in
            [Yy])
              while true; do
                read -p "请选择要重装的系统:  1. Debian12 | 2. Ubuntu20.04 : " sys_choice

                case "$sys_choice" in
                  1)
                    xitong="-d 12"
                    break  # 结束循环
                    ;;
                  2)
                    xitong="-u 20.04"
                    break  # 结束循环
                    ;;
                  *)
                    echo "无效的选择，请重新输入。"
                    ;;
                esac
              done

              read -p "请输入你重装后的密码: " vpspasswd
              install wget
              bash <(wget --no-check-certificate -qO- 'https://raw.githubusercontent.com/MoeClub/Note/master/InstallNET.sh') $xitong -v 64 -p $vpspasswd -port 22
              ;;
            [Nn])
              echo "已取消"
              ;;
            *)
              echo "无效的选择，请输入 Y 或 N。"
              ;;
          esac
              ;;

          6)
          dd_xitong_2() {
            echo -e "任意键继续，重装后初始用户名: ${huang}root${bai}  初始密码: ${huang}LeitboGi0ro${bai}  初始端口: ${huang}22${bai}"
            read -n 1 -s -r -p ""
            install wget
            wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
          }

          dd_xitong_3() {
            echo -e "任意键继续，重装后初始用户名: ${huang}Administrator${bai}  初始密码: ${huang}Teddysun.com${bai}  初始端口: ${huang}3389${bai}"
            read -n 1 -s -r -p ""
            install wget
            wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh' && chmod a+x InstallNET.sh
          }

          clear
          echo "请备份数据，将为你重装系统，预计花费15分钟。"
          read -p "确定继续吗？(Y/N): " choice

          case "$choice" in
            [Yy])
              while true; do

                echo "------------------------"
                echo "1. Debian 12"
                echo "------------------------"
                echo "2. Ubuntu 24.04"
                echo "3. Ubuntu 22.04"
                echo "------------------------"
                read -p "请选择要重装的系统: " sys_choice

                case "$sys_choice" in
                  1)
                    dd_xitong_2
                    bash InstallNET.sh -debian 12
                    reboot
                    exit
                    ;;
                  2)
                    dd_xitong_2
                    bash InstallNET.sh -ubuntu 24.04
                    reboot
                    exit
                    ;;
                  3)
                    dd_xitong_2
                    bash InstallNET.sh -ubuntu 22.04
                    reboot
                    exit
                    ;;
                  *)
                    echo "无效的选择，请重新输入。"
                    ;;
                esac
              done
              ;;
            [Nn])
              echo "已取消"
              ;;
            *)
              echo "无效的选择，请输入 Y 或 N。"
              ;;
          esac
              ;;

          7)
          clear
          current_hostname=$(hostname)
          echo "当前主机名: $current_hostname"
          read -p "是否要更改主机名？(y/n): " answer
          if [[ "${answer,,}" == "y" ]]; then
              # 获取新的主机名
              read -p "请输入新的主机名: " new_hostname
              if [ -n "$new_hostname" ]; then
                  if [ -f /etc/alpine-release ]; then
                      # Alpine
                      echo "$new_hostname" > /etc/hostname
                      hostname "$new_hostname"
                  else
                      # 其他系统，如 Debian, Ubuntu, CentOS 等
                      hostnamectl set-hostname "$new_hostname"
                      sed -i "s/$current_hostname/$new_hostname/g" /etc/hostname
                      systemctl restart systemd-hostnamed
                  fi
                  echo "主机名已更改为: $new_hostname"
              else
                  echo "无效的主机名。未更改主机名。"
                  exit 1
              fi
          else
              echo "未更改主机名。"
          fi
              ;;

          9)
              while true; do
                  clear
                  echo "定时任务列表"
                  crontab -l
                  echo ""
                  echo "操作"
                  echo "------------------------"
                  echo "1. 添加定时任务"
                  echo "2. 删除定时任务"                  
                  echo "------------------------"
                  echo "e. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -p "请输入新任务的执行命令: " newquest
                          echo "------------------------"
                          echo "1. 每周任务                 2. 每天任务"
                          read -p "请输入你的选择: " dingshi

                          case $dingshi in
                              1)
                                  read -p "选择周几执行任务？ (0-6，0代表星期日): " weekday
                                  (crontab -l ; echo "0 0 * * $weekday $newquest") | crontab - > /dev/null 2>&1
                                  ;;
                              2)
                                  read -p "选择每天几点执行任务？（小时，0-23）: " hour
                                  (crontab -l ; echo "0 $hour * * * $newquest") | crontab - > /dev/null 2>&1
                                  ;;
                              *)
                                  break  # 跳出
                                  ;;
                          esac
                          ;;
                      2)
                          read -p "请输入需要删除任务的关键字: " kquest
                          crontab -l | grep -v "$kquest" | crontab -
                          ;;
                      e)
                          break  # 跳出循环，退出菜单
                          ;;
                      *)
                          break  # 跳出循环，退出菜单
                          ;;
                  esac
              done
              ;;

          3)
              clear
              echo "设置你的ROOT密码"
              passwd
              sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config;
              sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config;
              rm -rf /etc/ssh/sshd_config.d/* /etc/ssh/ssh_config.d/*
              restart_ssh
              echo -e "${lv}ROOT登录设置完毕！${bai}"
              server_reboot
              ;;

        c)
           while true; do
            clear
            echo "▶ 甲骨文工具"
            echo "------------------------"
            echo "1. 安装活跃脚本"
            echo "2. 卸载活跃脚本"
            echo "------------------------"
            echo "e. 返回主菜单"
            echo "------------------------"
            read -p "请输入你的选择: " sub_choice

            case $sub_choice in
                1)
                    clear
                    echo "活跃脚本: CPU占用10-20% 内存占用15% "
                    read -p "确定安装吗？(Y/N): " choice
                    case "$choice" in
                      [Yy])

                        install_docker

                        docker run -itd --name=lookbusy --restart=always \
                                -e TZ=Asia/Shanghai \
                                -e CPU_UTIL=10-20 \
                                -e CPU_CORE=1 \
                                -e MEM_UTIL=15 \
                                -e SPEEDTEST_INTERVAL=120 \
                                fogforest/lookbusy
                        ;;
                      [Nn])
                        ;;
                      *)
                        echo "无效的选择，请输入 Y 或 N。"
                        ;;
                    esac
                    ;;
                2)
                    clear
                    docker rm -f lookbusy
                    docker rmi fogforest/lookbusy
                    ;;
                e)
                    break  # 跳出循环，退出菜单
                    ;;
                   esac
          done
          ;;
              
          e)
              rts
              ;;
          *)
              echo "无效的输入!"
              ;;

          r)
              clear
              server_reboot
              ;;
          e)
              rts
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end

    done
    ;;

  5)
    while true; do
      clear
      echo "▶ 测试工具"
      echo ""
      echo "----IP及解锁状态检测-----------"
      echo "1. ChatGPT解锁状态检测"
      echo "2. Region流媒体解锁测试"
      echo "3. yeahwu流媒体解锁检测"
      echo "4. xykt_IP质量检测"
      echo ""
      echo "----网络线路测速-----------"
      echo "11. besttrace三网回程延迟路由测试"
      echo "12. mtr_trace三网回程线路测试"
      echo "13. Superspeed三网测速"
      echo "14. nxtrace快速回程测试脚本"
      echo "15. nxtrace指定IP回程测试脚本"
      echo "16. ludashi2020三网线路测试"
      echo ""
      echo "----硬件性能测试----------"
      echo "21. yabs性能测试"
      echo "22. icu/gb5 CPU性能测试脚本"
      echo ""
      echo "----综合性测试-----------"
      echo "31. bench性能测试"
      echo "32. spiritysdx融合怪测评"
      echo ""
      echo "------------------------"
      echo "e. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          1)
              clear
              bash <(curl -Ls https://cdn.jsdelivr.net/gh/missuo/OpenAI-Checker/openai.sh)
              ;;
          2)
              clear
              bash <(curl -L -s check.unlock.media)
              ;;
          3)
              clear
              install wget
              wget -qO- https://github.com/yeahwu/check/raw/main/check.sh | bash
              ;;
          4)
              clear
              bash <(curl -Ls IP.Check.Place)
              ;;
          11)
              clear
              install wget
              wget -qO- git.io/besttrace | bash
              ;;
          12)
              clear
              curl https://raw.githubusercontent.com/zhucaidan/mtr_trace/main/mtr_trace.sh | bash
              ;;
          13)
              clear
              bash <(curl -Lso- https://git.io/superspeed_uxh)
              ;;
          14)
              clear
              curl nxtrace.org/nt |bash
              nexttrace --fast-trace --tcp
              ;;
          15)
              clear

              echo "可参考的IP列表"
              echo "------------------------"
              echo "北京电信: 219.141.136.12"
              echo "北京联通: 202.106.50.1"
              echo "北京移动: 221.179.155.161"
              echo "上海电信: 202.96.209.133"
              echo "上海联通: 210.22.97.1"
              echo "上海移动: 211.136.112.200"
              echo "广州电信: 58.60.188.222"
              echo "广州联通: 210.21.196.6"
              echo "广州移动: 120.196.165.24"
              echo "成都电信: 61.139.2.69"
              echo "成都联通: 119.6.6.6"
              echo "成都移动: 211.137.96.205"
              echo "湖南电信: 36.111.200.100"
              echo "湖南联通: 42.48.16.100"
              echo "湖南移动: 39.134.254.6"
              echo "------------------------"

              read -p "输入一个指定IP: " testip
              curl nxtrace.org/nt |bash
              nexttrace $testip
              ;;

          16)
              clear
              curl https://raw.githubusercontent.com/ludashi2020/backtrace/main/install.sh -sSf | sh
              ;;

          21)
              clear
              new_swap=1024
              add_swap
              curl -sL yabs.sh | bash -s -- -i -5
              ;;
          22)
              clear
              new_swap=1024
              add_swap
              bash <(curl -sL bash.icu/gb5)
              ;;

          31)
              clear
              curl -Lso- bench.sh | bash
              ;;
          32)
              clear
              curl -L https://gitlab.com/spiritysdx/za/-/raw/main/ecs.sh -o ecs.sh && chmod +x ecs.sh && bash ecs.sh
              ;;

          e)
              rts
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end

    done
    ;;

  6)
  while true; do
      clear
      echo "▶ 安装常用工具"
      echo "------------------------"
      echo "1. curl 下载工具"
      echo "2. wget 下载工具"
      echo "3. sudo 超级管理权限工具"
      echo "4. socat 通信连接工具 （申请域名证书必备）"
      echo "5. htop 系统监控工具"
      echo "6. iftop 网络流量监控工具"
      echo "7. unzip ZIP压缩解压工具"
      echo "8. tar GZ压缩解压工具"
      echo "9. tmux 多路后台运行工具"
      echo "10. ffmpeg 视频编码直播推流工具"
      echo "11. btop 现代化监控工具"
      echo "12. ranger 文件管理工具"
      echo "13. gdu 磁盘占用查看工具"
      echo "14. fzf 全局搜索工具"
      echo "------------------------"
      echo "21. 全部安装"
      echo "22. 全部卸载"
      echo "------------------------"
      echo "31. 安装指定工具"
      echo "32. 卸载指定工具"
      echo "------------------------"
      echo "e. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
            1)
              clear
              install curl
              clear
              echo "工具已安装，使用方法如下："
              curl --help
              ;;
            2)
              clear
              install wget
              clear
              echo "工具已安装，使用方法如下："
              wget --help
              ;;
            3)
              clear
              install sudo
              clear
              echo "工具已安装，使用方法如下："
              sudo --help
              ;;
            4)
              clear
              install socat
              clear
              echo "工具已安装，使用方法如下："
              socat -h
              ;;
            5)
              clear
              install htop
              clear
              htop
              ;;
            6)
              clear
              install iftop
              clear
              iftop
              ;;
            7)
              clear
              install unzip
              clear
              echo "工具已安装，使用方法如下："
              unzip
              ;;
            8)
              clear
              install tar
              clear
              echo "工具已安装，使用方法如下："
              tar --help
              ;;
            9)
              clear
              install tmux
              clear
              echo "工具已安装，使用方法如下："
              tmux --help
              ;;
            10)
              clear
              install ffmpeg
              clear
              echo "工具已安装，使用方法如下："
              ffmpeg --help
              ;;
            11)
              clear
              install btop
              clear
              btop
              ;;
            12)
              clear
              install ranger
              cd /
              clear
              ranger
              cd ~
              ;;
            13)
              clear
              install gdu
              cd /
              clear
              gdu
              cd ~
              ;;
            14)
              clear
              install fzf
              cd /
              clear
              fzf
              cd ~
              ;;
          21)
              clear
              install curl wget sudo socat htop iftop unzip tar tmux ffmpeg btop ranger gdu fzf
              ;;
          22)
              clear
              remove htop iftop unzip tmux ffmpeg btop ranger gdu fzf
              ;;
          31)
              clear
              read -p "请输入安装的工具名（wget curl sudo htop）: " installname
              install $installname
              ;;
          32)
              clear
              read -p "请输入卸载的工具名（htop ufw tmux cmatrix）: " removename
              remove $removename
              ;;
          e)
              rts
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end
  done

    ;;

  8)
    while true; do
      clear
      echo "▶ Docker管理器"
      echo "------------------------"
      echo "1. 安装更新Docker环境"
      echo "------------------------"
      echo "2. 查看Dcoker全局状态"
      echo "------------------------"
      echo "3. Dcoker容器管理 ▶"
      echo "4. Dcoker镜像管理 ▶"
      echo "5. Dcoker网络管理 ▶"
      echo "6. Dcoker卷管理 ▶"
      echo "------------------------"
      echo "7. 清理无用的docker容器和镜像网络数据卷"
      echo "------------------------"
      echo "8. 卸载Dcoker环境"
      echo "------------------------"
      echo "e. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          1)
            clear
            install_add_docker
              ;;
          2)
              clear
              echo "Dcoker版本"
              docker --version
              docker-compose --version
              echo ""
              echo "Dcoker镜像列表"
              docker image ls
              echo ""
              echo "Dcoker容器列表"
              docker ps -a
              echo ""
              echo "Dcoker卷列表"
              docker volume ls
              echo ""
              echo "Dcoker网络列表"
              docker network ls
              echo ""
              ;;
          3)
              while true; do
                  clear
                  echo "Docker容器列表"
                  docker ps -a
                  echo ""
                  echo "容器操作"
                  echo "------------------------"
                  echo "1. 创建新的容器"
                  echo "------------------------"
                  echo "2. 启动指定容器             6. 启动所有容器"
                  echo "3. 停止指定容器             7. 暂停所有容器"
                  echo "4. 删除指定容器             8. 删除所有容器"
                  echo "5. 重启指定容器             9. 重启所有容器"
                  echo "------------------------"
                  echo "10. 进入指定容器           11. 查看容器日志           12. 查看容器网络"
                  echo "------------------------"
                  echo "e. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -p "请输入创建命令: " dockername
                          $dockername
                          ;;
                      2)
                          read -p "请输入容器名: " dockername
                          docker start $dockername
                          ;;
                      3)
                          read -p "请输入容器名: " dockername
                          docker stop $dockername
                          ;;
                      4)
                          read -p "请输入容器名: " dockername
                          docker rm -f $dockername
                          ;;
                      5)
                          read -p "请输入容器名: " dockername
                          docker restart $dockername
                          ;;
                      6)
                          docker start $(docker ps -a -q)
                          ;;
                      7)
                          docker stop $(docker ps -q)
                          ;;
                      8)
                          read -p "" choice
                          read -p "$(echo -e "确定${hong}删除所有容器${bai}吗？(Y/N): ")" choice
                          case "$choice" in
                            [Yy])
                              docker rm -f $(docker ps -a -q)
                              ;;
                            [Nn])
                              ;;
                            *)
                              echo "无效的选择，请输入 Y 或 N。"
                              ;;
                          esac
                          ;;
                      9)
                          docker restart $(docker ps -q)
                          ;;
                      10)
                          read -p "请输入容器名: " dockername
                          docker exec -it $dockername /bin/sh
                          break_end
                          ;;
                      11)
                          read -p "请输入容器名: " dockername
                          docker logs $dockername
                          break_end
                          ;;
                      12)
                          echo ""
                          container_ids=$(docker ps -q)

                          echo "------------------------------------------------------------"
                          printf "%-25s %-25s %-25s\n" "容器名称" "网络名称" "IP地址"

                          for container_id in $container_ids; do
                              container_info=$(docker inspect --format '{{ .Name }}{{ range $network, $config := .NetworkSettings.Networks }} {{ $network }} {{ $config.IPAddress }}{{ end }}' "$container_id")

                              container_name=$(echo "$container_info" | awk '{print $1}')
                              network_info=$(echo "$container_info" | cut -d' ' -f2-)

                              while IFS= read -r line; do
                                  network_name=$(echo "$line" | awk '{print $1}')
                                  ip_address=$(echo "$line" | awk '{print $2}')

                                  printf "%-20s %-20s %-15s\n" "$container_name" "$network_name" "$ip_address"
                              done <<< "$network_info"
                          done

                          break_end
                          ;;
                      e)
                          break  # 跳出循环，退出菜单
                          ;;
                      *)
                          break  # 跳出循环，退出菜单
                          ;;
                  esac
              done
              ;;
          4)
              while true; do
                  clear
                  echo "Docker镜像列表"
                  docker image ls
                  echo ""
                  echo "镜像操作"
                  echo "------------------------"
                  echo "1. 获取指定镜像"
                  echo "2. 更新指定镜像"
                  echo "3. 删除指定镜像"
                  echo "4. 删除所有镜像"                  
                  echo "------------------------"
                  echo "e. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -p "请输入镜像名: " dockername
                          docker pull $dockername
                          ;;
                      2)
                          read -p "请输入镜像名: " dockername
                          docker pull $dockername
                          ;;
                      3)
                          read -p "请输入镜像名: " dockername
                          docker rmi -f $dockername
                          ;;
                      4)
                          read -p "$(echo -e "确定${hong}删除所有镜像${bai}吗？(Y/N): ")" choice
                          case "$choice" in
                            [Yy])
                              docker rmi -f $(docker images -q)
                              ;;
                            [Nn])

                              ;;
                            *)
                              echo "无效的选择，请输入 Y 或 N。"
                              ;;
                          esac
                          ;;
                      e)
                          break  # 跳出循环，退出菜单
                          ;;
                      *)
                          break  # 跳出循环，退出菜单
                          ;;
                  esac
              done
              ;;

          5)
              while true; do
                  clear
                  echo "Docker网络列表"
                  echo "------------------------------------------------------------"
                  docker network ls
                  echo ""

                  echo "------------------------------------------------------------"
                  container_ids=$(docker ps -q)
                  printf "%-25s %-25s %-25s\n" "容器名称" "网络名称" "IP地址"

                  for container_id in $container_ids; do
                      container_info=$(docker inspect --format '{{ .Name }}{{ range $network, $config := .NetworkSettings.Networks }} {{ $network }} {{ $config.IPAddress }}{{ end }}' "$container_id")

                      container_name=$(echo "$container_info" | awk '{print $1}')
                      network_info=$(echo "$container_info" | cut -d' ' -f2-)

                      while IFS= read -r line; do
                          network_name=$(echo "$line" | awk '{print $1}')
                          ip_address=$(echo "$line" | awk '{print $2}')

                          printf "%-20s %-20s %-15s\n" "$container_name" "$network_name" "$ip_address"
                      done <<< "$network_info"
                  done

                  echo ""
                  echo "网络操作"
                  echo "------------------------"
                  echo "1. 创建网络"
                  echo "2. 加入网络"
                  echo "3. 退出网络"
                  echo "4. 删除网络"
                  echo "------------------------"
                  echo "e. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -p "设置新网络名: " dockernetwork
                          docker network create $dockernetwork
                          ;;
                      2)
                          read -p "加入网络名: " dockernetwork
                          read -p "那些容器加入该网络: " dockername
                          docker network connect $dockernetwork $dockername
                          echo ""
                          ;;
                      3)
                          read -p "退出网络名: " dockernetwork
                          read -p "那些容器退出该网络: " dockername
                          docker network disconnect $dockernetwork $dockername
                          echo ""
                          ;;
                      4)
                          read -p "请输入要删除的网络名: " dockernetwork
                          docker network rm $dockernetwork
                          ;;
                      e)
                          break  # 跳出循环，退出菜单
                          ;;
                      *)
                          break  # 跳出循环，退出菜单
                          ;;
                  esac
              done
              ;;

          6)
              while true; do
                  clear
                  echo "Docker卷列表"
                  docker volume ls
                  echo ""
                  echo "卷操作"
                  echo "------------------------"
                  echo "1. 创建新卷"
                  echo "2. 删除卷"
                  echo "------------------------"
                  echo "e. 返回上一级选单"
                  echo "------------------------"
                  read -p "请输入你的选择: " sub_choice

                  case $sub_choice in
                      1)
                          read -p "设置新卷名: " dockerjuan
                          docker volume create $dockerjuan
                          ;;
                      2)
                          read -p "输入删除卷名: " dockerjuan
                          docker volume rm $dockerjuan
                          ;;
                      e)
                          break  # 跳出循环，退出菜单
                          ;;
                      *)
                          break  # 跳出循环，退出菜单
                          ;;
                  esac
              done
              ;;
          7)
              clear
              read -p "$(echo -e "确定${huang}清理无用的镜像容器网络${bai}吗？(Y/N): ")" choice
              case "$choice" in
                [Yy])
                  docker system prune -af --volumes
                  ;;
                [Nn])
                  ;;
                *)
                  echo "无效的选择，请输入 Y 或 N。"
                  ;;
              esac
              ;;
          8)
              clear
              read -p "$(echo -e "确定${hong}卸载docker环境${bai}吗？(Y/N): ")" choice
              case "$choice" in
                [Yy])
                  docker rm $(docker ps -a -q) && docker rmi $(docker images -q) && docker network prune
                  remove docker > /dev/null 2>&1
                  ;;
                [Nn])
                  ;;
                *)
                  echo "无效的选择，请输入 Y 或 N。"
                  ;;
              esac
              ;;
          e)
              rts
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end

    done
    ;;

  7)
    while true; do
      clear
      echo "▶ 面板工具"
      echo "------------------------"
      echo "1. 1Panel管理面板"
      echo "2. NginxProxyManager面板"      
      echo "3. LibreSpeed测速工具"
      echo "4. Speedtest测速工具"            
      echo "------------------------"
      echo "e. 返回主菜单"
      echo "------------------------"
      read -p "请输入你的选择: " sub_choice

      case $sub_choice in
          1)
            lujing="command -v 1pctl &> /dev/null"
            panelname="1Panel"

            gongneng1="1pctl user-info"
            gongneng1_1="1pctl update password"
            gongneng2="1pctl uninstall"
            gongneng2_1=""
            gongneng2_2=""

            panelurl="https://1panel.cn/"


            centos_mingling="curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh"
            centos_mingling2="sh quick_start.sh"

            ubuntu_mingling="curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh"
            ubuntu_mingling2="bash quick_start.sh"
            install_panel
              ;;             
          2)

            docker_name="npm"
            docker_img="jc21/nginx-proxy-manager:latest"
            docker_port=81
            docker_rum="docker run -d \
                          --name=$docker_name \
                          -p 80:80 \
                          -p 81:$docker_port \
                          -p 443:443 \
                          -v /home/docker/npm/data:/data \
                          -v /home/docker/npm/letsencrypt:/etc/letsencrypt \
                          --restart=always \
                          $docker_img"
            docker_describe="如果您已经安装了其他面板工具或者LDNMP建站环境，建议先卸载，再安装npm！"
            docker_url="官网介绍: https://nginxproxymanager.com/"
            docker_use="echo \"初始用户名: admin@example.com\""
            docker_passwd="echo \"初始密码: changeme\""
            docker_app
              ;;
          3)
            docker_name="speedtest"
            docker_img="ghcr.io/librespeed/speedtest:latest"
            docker_port=6681
            docker_rum="docker run -d \
                            --name speedtest \
                            --restart always \
                            -e MODE=standalone \
                            -p 6681:80 \
                            ghcr.io/librespeed/speedtest:latest"
            docker_describe="librespeed是用Javascript实现的轻量级速度测试工具，即开即用"
            docker_url="官网介绍: https://github.com/librespeed/speedtest"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;
          4)
            docker_name="looking-glass"
            docker_img="wikihostinc/looking-glass-server"
            docker_port=89
            docker_rum="docker run -d --name looking-glass --restart always -p 89:80 wikihostinc/looking-glass-server"
            docker_describe="Speedtest测速面板是一个VPS网速测试工具，多项测试功能，还可以实时监控VPS进出站流量"
            docker_url="官网介绍: https://github.com/wikihost-opensource/als"
            docker_use=""
            docker_passwd=""
            docker_app
              ;;
          e)
              rts
              ;;
          *)
              echo "无效的输入!"
              ;;
      esac
      break_end

    done
    ;;  

  e)
    clear
    exit
    ;;
    
  i)
    clear
    uninstall
    exit
    ;;

  *)
    echo "无效的输入!"
    ;;
esac
    break_end
done
