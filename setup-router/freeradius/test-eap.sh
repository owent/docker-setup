#!/bin/bash
#=============================================================================
# FreeRADIUS EAP 认证测试脚本
# 
# 用法:
#   ./test-eap.sh                    # 使用默认配置测试
#   ./test-eap.sh -h 192.168.1.1     # 指定 RADIUS 服务器
#   ./test-eap.sh -s mysecret        # 指定客户端密钥
#   ./test-eap.sh -u testuser -p password  # 指定测试用户
#   ./test-eap.sh --eapol            # 使用 eapol_test 进行完整测试
#=============================================================================

set -e

# 默认配置
RADIUS_HOST="${RADIUS_HOST:-127.0.0.1}"
RADIUS_SECRET="${RADIUS_SECRET:-Xy9-mP2@kL_5vR!z}"
AUTH_PORT="${AUTH_PORT:-1812}"
ACCT_PORT="${ACCT_PORT:-1813}"
TEST_USER="${TEST_USER:-testuser}"
TEST_PASS="${TEST_PASS:-password123}"
USE_EAPOL="${USE_EAPOL:-no}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#----------------------------------------------------------------------------
# 解析命令行参数
#----------------------------------------------------------------------------
usage() {
    cat << EOF
用法: $0 [选项]

选项:
    -h, --host HOST         RADIUS 服务器地址 (默认: 127.0.0.1)
    -p, --port PORT         RADIUS 认证端口 (默认: 1812)
    -s, --secret SECRET     RADIUS 客户端密钥 (默认: Xy9-mP2@kL_5vR!z)
    -u, --user USER         测试用户名 (默认: testuser)
    -P, --password PASS     测试用户密码 (默认: password123)
    -e, --eapol            使用 eapol_test 进行完整测试
    --help                 显示此帮助信息

示例:
    $0
    $0 -h 192.168.1.100 -s mysecret
    $0 --eapol
EOF
    exit 0
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--host)
            RADIUS_HOST="$2"
            shift 2
            ;;
        -p|--port)
            AUTH_PORT="$2"
            shift 2
            ;;
        -s|--secret)
            RADIUS_SECRET="$2"
            shift 2
            ;;
        -u|--user)
            TEST_USER="$2"
            shift 2
            ;;
        -P|--password)
            TEST_PASS="$2"
            shift 2
            ;;
        -e|--eapol)
            USE_EAPOL="yes"
            shift
            ;;
        --help)
            usage
            ;;
        *)
            echo "未知选项: $1"
            usage
            ;;
    esac
done

#----------------------------------------------------------------------------
# 辅助函数
#----------------------------------------------------------------------------
print_header() {
    echo ""
    echo "========================================"
    echo "$1"
    echo "========================================"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}! $1${NC}"
}

print_info() {
    echo -e "  $1"
}

#----------------------------------------------------------------------------
# 检查依赖
#----------------------------------------------------------------------------
check_dependencies() {
    print_header "检查依赖"
    
    local missing=()
    
    # 检查 radtest/radclient
    if ! command -v radtest &> /dev/null && ! command -v radclient &> /dev/null; then
        missing+=("freeradius-utils (radtest/radclient)")
    else
        print_success "freeradius-utils"
    fi
    
    # 检查 nc (netcat)
    if ! command -v nc &> /dev/null; then
        missing+=("netcat")
    else
        print_success "netcat"
    fi
    
    # 检查 eapol_test (可选)
    if command -v eapol_test &> /dev/null; then
        print_success "eapol_test (可用)"
    else
        print_warning "eapol_test (未安装, 跳过完整EAP测试)"
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo ""
        print_warning "缺少依赖，请安装:"
        for dep in "${missing[@]}"; do
            echo "  - $dep"
        done
        echo ""
        echo "安装命令:"
        echo "  Debian/Ubuntu: apt-get install freeradius-utils netcat-openbsd"
        echo "  Alpine: apk add freeradius-client netcat"
        return 1
    fi
    
    return 0
}

#----------------------------------------------------------------------------
# 测试1: 基本连通性
#----------------------------------------------------------------------------
test_connectivity() {
    print_header "测试基本连通性"
    
    print_info "RADIUS 服务器: $RADIUS_HOST:$AUTH_PORT"
    
    if nc -z -w3 "$RADIUS_HOST" "$AUTH_PORT" 2>/dev/null; then
        print_success "RADIUS 端口 $AUTH_PORT 可达"
        return 0
    else
        print_error "无法连接到 RADIUS 服务器 $RADIUS_HOST:$AUTH_PORT"
        return 1
    fi
}

#----------------------------------------------------------------------------
# 测试2: PAP 认证
#----------------------------------------------------------------------------
test_pap() {
    print_header "测试 PAP 认证"
    
    print_info "用户名: $TEST_USER"
    print_info "密码: $TEST_PASS"
    
    # 使用 radtest 进行 PAP 测试
    local result
    if result=$(echo "User-Name = $TEST_USER, User-Password = $TEST_PASS" | \
        radclient -x "$RADIUS_HOST:$AUTH_PORT" auth "$RADIUS_SECRET" 2>&1); then
        
        if echo "$result" | grep -q "Access-Accept"; then
            print_success "PAP 认证成功 (Access-Accept)"
            return 0
        elif echo "$result" | grep -q "Access-Reject"; then
            print_error "PAP 认证被拒绝 (Access-Reject)"
            print_info "可能原因: 用户名/密码错误, LDAP 配置问题"
            return 1
        fi
    fi
    
    # radtest 可能返回非零但依然有输出
    if echo "$result" | grep -q "Access-Accept"; then
        print_success "PAP 认证成功 (Access-Accept)"
        return 0
    fi
    
    print_error "PAP 认证失败"
    print_info "详情: $result"
    return 1
}

#----------------------------------------------------------------------------
# 测试3: 检查 FreeRADIUS 容器状态
#----------------------------------------------------------------------------
test_freeradius_status() {
    print_header "检查 FreeRADIUS 服务状态"
    
    # 检查容器是否运行
    if command -v podman &> /dev/null; then
        if podman ps --format "{{.Names}}" | grep -q "^freeradius$"; then
            print_success "FreeRADIUS 容器运行中"
        else
            print_warning "FreeRADIUS 容器未运行 (podman)"
        fi
    fi
    
    if command -v docker &> /dev/null; then
        if docker ps --format "{{.Names}}" | grep -q "^freeradius$"; then
            print_success "FreeRADIUS 容器运行中 (docker)"
        else
            print_warning "FreeRADIUS 容器未运行 (docker)"
        fi
    fi
    
    # 检查配置
    if [[ -d "$HOME/.config/containers/systemd" ]] || \
       [[ -d "/etc/systemd/user" ]]; then
        print_info "systemd 服务: container-freeradius.service"
        if systemctl --user is-active container-freeradius &>/dev/null; then
            print_success "服务已启动"
        else
            print_warning "服务未启动"
        fi
    fi
}

#----------------------------------------------------------------------------
# 测试4: EAP-TTLS 配置检查
#----------------------------------------------------------------------------
test_eap_config() {
    print_header "检查 EAP 配置"
    
    local config_found=0
    
    # 检查 EAP 模块
    if [[ -d "./config" ]]; then
        if [[ -f "./config/mods-enabled/eap" ]]; then
            print_success "EAP 模块已启用"
            config_found=1
        fi
    elif [[ -d "./etc" ]]; then
        if [[ -f "./etc/mods-available/eap" ]]; then
            print_success "EAP 模块配置文件存在"
            config_found=1
        fi
    fi
    
    # 检查客户端配置
    if [[ -f "./etc/clients.conf" ]]; then
        print_success "客户端配置文件存在"
        print_info "默认密钥: Xy9-mP2@kL_5vR!z"
    fi
    
    if [[ $config_found -eq 0 ]]; then
        print_warning "未找到 EAP 配置，请先运行 create-pod-systemd.sh"
    fi
}

#----------------------------------------------------------------------------
# 测试5: eapol_test 完整 EAP 测试
#----------------------------------------------------------------------------
test_eapol() {
    print_header "使用 eapol_test 进行完整 EAP 测试"
    
    if ! command -v eapol_test &> /dev/null; then
        print_warning "eapol_test 未安装，跳过此测试"
        print_info "可以使用 Docker 运行:"
        print_info "  docker run --rm -it --network host"
        print_info "    -v \$(pwd)/eapol_test.conf:/test.conf"
        print_info "    w1f9a2n/eapol_test"
        print_info "    eapol_test -c /test.conf -s $RADIUS_HOST -a $AUTH_PORT"
        return 0
    fi
    
    # 创建临时测试配置
    local tmp_conf="/tmp/eapol_test_$$.conf"
    cat > "$tmp_conf" << EOF
network={
    ssid="test"
    key_mgmt=WPA-EAP
    eap=TTLS
    identity="$TEST_USER"
    anonymous_identity="anonymous"
    password="$TEST_PASS"
    phase2="auth=PAP"
}
EOF
    
    print_info "测试配置已创建: $tmp_conf"
    
    # 运行测试
    if eapol_test -c "$tmp_conf" -s "$RADIUS_HOST" -a "$AUTH_PORT" \
        -M 00:11:22:33:44:55 -N 25:s00:00:00:00:00:00 2>&1 | \
        grep -q "Authentication completed"; then
        print_success "EAP-TTLS/PAP 认证成功"
    else
        print_error "EAP-TTLS/PAP 认证失败"
    fi
    
    # 清理
    rm -f "$tmp_conf"
}

#----------------------------------------------------------------------------
# 测试6: 调试模式说明
#----------------------------------------------------------------------------
show_debug_info() {
    print_header "调试信息"
    
    print_info "要启用详细调试，运行:"
    echo ""
    echo "  # 停止服务"
    echo "  systemctl --user stop container-freeradius"
    echo ""
    echo "  # 前台运行 FreeRADIUS (查看实时日志)"
    echo "  podman exec -it freeradius radiusd -X"
    echo ""
    echo "  # 或者查看日志"
    echo "  podman logs -f freeradius"
    echo ""
}

#----------------------------------------------------------------------------
# 主函数
#----------------------------------------------------------------------------
main() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   FreeRADIUS EAP 认证测试工具           ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "RADIUS 服务器: $RADIUS_HOST:$AUTH_PORT"
    echo "测试用户: $TEST_USER"
    echo ""
    
    # 检查依赖
    if ! check_dependencies; then
        exit 1
    fi
    
    # 执行测试
    local failed=0
    
    test_connectivity || failed=1
    test_pap || failed=1
    test_freeradius_status
    test_eap_config
    
    if [[ "$USE_EAPOL" == "yes" ]]; then
        test_eapol
    fi
    
    show_debug_info
    
    # 总结
    print_header "测试结果"
    if [[ $failed -eq 0 ]]; then
        print_success "所有测试通过!"
    else
        print_error "部分测试失败，请检查配置"
    fi
}

# 运行主函数
main

