#!/bin/bash

# HAProxy 后端状态监控脚本
# 检测后端状态变更并发送飞书通知

# 配置区域
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
STATE_FILE="${STATE_FILE:-/tmp/haproxy-monitor-state.json}"
HAPROXY_SOCKET="${HAPROXY_SOCKET:-/var/run/haproxy.sock}"
HAPROXY_STATS_URL="${HAPROXY_STATS_URL:-http://127.0.0.1:8404/stats}"
FEISHU_WEBHOOK_URL="${FEISHU_WEBHOOK_URL}"

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# 检查必需的配置
if [[ -z "$FEISHU_WEBHOOK_URL" ]]; then
    log "ERROR: FEISHU_WEBHOOK_URL is not set"
    exit 1
fi

# 检查依赖命令
for cmd in jq curl; do
    if ! command -v $cmd &> /dev/null; then
        log "ERROR: $cmd is required but not installed"
        exit 1
    fi
done

# 获取 HAProxy 状态信息
get_haproxy_stats() {
    # 优先使用 socket，如果不存在则使用 HTTP stats
    if [[ -e "$HAPROXY_SOCKET" ]]; then
        echo "show stat" | socat stdio unix-connect:"$HAPROXY_SOCKET" 2>/dev/null | grep -v "^#"
    elif command -v podman &> /dev/null; then
        # 通过容器执行命令获取状态
        podman exec haproxy sh -c "echo 'show stat' | socat stdio /var/run/haproxy.sock" 2>/dev/null | grep -v "^#"
    elif command -v docker &> /dev/null; then
        # 如果使用 docker
        docker exec haproxy sh -c "echo 'show stat' | socat stdio /var/run/haproxy.sock" 2>/dev/null | grep -v "^#"
    else
        log "ERROR: Cannot connect to HAProxy stats"
        return 1
    fi
}

# 解析 HAProxy CSV 格式的统计数据
parse_haproxy_stats() {
    local stats="$1"
    local result="{"
    local first=true
    
    echo "$stats" | while IFS=',' read -r pxname svname qcur qmax scur smax slim stot bin bout dreq dresp ereq econ eresp wretr wredis status weight act bck chkfail chkdown lastchg downtime qlimit pid iid sid throttle lbtot tracked type rate rate_lim rate_max check_status check_code check_duration hrsp_1xx hrsp_2xx hrsp_3xx hrsp_4xx hrsp_5xx hrsp_other hanafail req_rate req_rate_max req_tot cli_abrt srv_abrt comp_in comp_out comp_byp comp_rsp lastsess last_chk last_agt qtime ctime rtime ttime agent_status agent_code agent_duration check_desc agent_desc check_rise check_fall check_health agent_rise agent_fall agent_health addr cookie mode algo conn_rate conn_rate_max conn_tot intercepted dcon dses wrew connect reuse cache_lookups cache_hits ssl_sess ssl_reused ssl_failed ssl_handshake_failures ssl_no_reused_session_id rest; do
        # 只处理后端服务器（type=2）和后端（type=1）
        if [[ "$type" == "2" ]] || [[ "$type" == "1" ]]; then
            # 创建唯一键
            local key="${pxname}/${svname}"
            
            # 构建 JSON
            if [[ "$first" != true ]]; then
                result+=","
            fi
            first=false
            
            result+="\"$key\":{\"status\":\"$status\",\"weight\":\"$weight\",\"lastchg\":\"$lastchg\",\"check_status\":\"$check_status\"}"
        fi
    done
    result+="}"
    
    echo "$result"
}

# 发送飞书通知
send_feishu_notification() {
    local title="$1"
    local message="$2"
    local color="${3:-blue}"
    
    # 根据状态选择颜色
    case "$color" in
        error|down)
            color="red"
            ;;
        warning)
            color="orange"
            ;;
        success|up)
            color="green"
            ;;
        *)
            color="blue"
            ;;
    esac
    
    local payload=$(cat <<EOF
{
    "msg_type": "interactive",
    "card": {
        "header": {
            "title": {
                "content": "$title",
                "tag": "plain_text"
            },
            "template": "$color"
        },
        "elements": [
            {
                "tag": "div",
                "text": {
                    "content": "$message",
                    "tag": "lark_md"
                }
            },
            {
                "tag": "note",
                "elements": [
                    {
                        "tag": "plain_text",
                        "content": "时间: $(date '+%Y-%m-%d %H:%M:%S')"
                    }
                ]
            }
        ]
    }
}
EOF
)
    
    local response=$(curl -s -w "\n%{http_code}" -X POST "$FEISHU_WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | head -n-1)
    
    if [[ "$http_code" == "200" ]]; then
        log "Feishu notification sent successfully"
        return 0
    else
        log "ERROR: Failed to send Feishu notification (HTTP $http_code): $body"
        return 1
    fi
}

# 比较状态并检测变更
compare_states() {
    local old_state="$1"
    local new_state="$2"
    local changes=""
    local change_count=0
    
    # 遍历新状态
    for key in $(echo "$new_state" | jq -r 'keys[]'); do
        local old_status=$(echo "$old_state" | jq -r --arg key "$key" '.[$key].status // "UNKNOWN"')
        local new_status=$(echo "$new_state" | jq -r --arg key "$key" '.[$key].status')
        local new_check=$(echo "$new_state" | jq -r --arg key "$key" '.[$key].check_status')
        
        # 检测状态变更
        if [[ "$old_status" != "$new_status" ]] && [[ "$old_status" != "UNKNOWN" ]]; then
            change_count=$((change_count + 1))
            local backend=$(echo "$key" | cut -d'/' -f1)
            local server=$(echo "$key" | cut -d'/' -f2)
            
            # 判断状态类型
            local status_icon="🔵"
            local status_type="info"
            if [[ "$new_status" == "UP" ]]; then
                status_icon="✅"
                status_type="success"
            elif [[ "$new_status" =~ ^DOWN ]]; then
                status_icon="❌"
                status_type="error"
            elif [[ "$new_status" =~ ^MAINT ]]; then
                status_icon="🔧"
                status_type="warning"
            elif [[ "$new_status" =~ ^NOLB ]]; then
                status_icon="⚠️"
                status_type="warning"
            fi
            
            changes+="**后端**: \`$backend\`\n"
            changes+="**服务器**: \`$server\`\n"
            changes+="**状态变更**: \`$old_status\` → \`$new_status\` $status_icon\n"
            if [[ -n "$new_check" ]] && [[ "$new_check" != "null" ]]; then
                changes+="**健康检查**: $new_check\n"
            fi
            changes+="\n---\n\n"
            
            # 记录日志
            log "Status changed: $backend/$server: $old_status -> $new_status"
        fi
    done
    
    # 检测新增的后端
    for key in $(echo "$new_state" | jq -r 'keys[]'); do
        local exists=$(echo "$old_state" | jq -r --arg key "$key" 'has($key)')
        if [[ "$exists" == "false" ]]; then
            change_count=$((change_count + 1))
            local backend=$(echo "$key" | cut -d'/' -f1)
            local server=$(echo "$key" | cut -d'/' -f2)
            local new_status=$(echo "$new_state" | jq -r --arg key "$key" '.[$key].status')
            
            changes+="**后端**: \`$backend\`\n"
            changes+="**服务器**: \`$server\`\n"
            changes+="**状态**: 新增后端 (状态: \`$new_status\`) 🆕\n"
            changes+="\n---\n\n"
            
            log "New backend detected: $backend/$server ($new_status)"
        fi
    done
    
    # 发送通知
    if [[ $change_count -gt 0 ]]; then
        local title="HAProxy 后端状态变更通知"
        if [[ $change_count -eq 1 ]]; then
            title="HAProxy 后端状态变更"
        else
            title="HAProxy 后端状态变更 (${change_count} 项)"
        fi
        
        send_feishu_notification "$title" "$changes" "warning"
    else
        log "No status changes detected"
    fi
    
    return $change_count
}

# 主函数
main() {
    log "Starting HAProxy backend status monitoring"
    
    # 获取当前状态
    local stats=$(get_haproxy_stats)
    if [[ -z "$stats" ]]; then
        log "ERROR: Failed to get HAProxy stats"
        exit 1
    fi
    
    # 解析状态
    local current_state=$(parse_haproxy_stats "$stats")
    
    # 读取旧状态
    local old_state="{}"
    if [[ -f "$STATE_FILE" ]]; then
        old_state=$(cat "$STATE_FILE")
    else
        log "INFO: No previous state file found, creating new one"
    fi
    
    # 比较状态
    compare_states "$old_state" "$current_state"
    
    # 保存当前状态
    echo "$current_state" > "$STATE_FILE"
    
    log "Monitoring check completed"
}

# 运行主函数
main "$@"
