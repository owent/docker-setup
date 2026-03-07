# OpenClaw 部署与使用说明

本文档从 `start-openclaw.sh` 中的注释整理而来，并补充了以下内容：

- agent 的常用管理命令
- 多 agent 的配置思路
- ClawHub 的使用方法

当前目录中的脚本默认使用 Podman 部署 OpenClaw，并把配置、技能、扩展、工作区分别映射到宿主机目录。

## 1. 项目入口与参考文档

- OpenClaw 项目：<https://github.com/openclaw/openclaw>
- Docker 安装：<https://docs.openclaw.ai/install/docker>
- Podman 安装：<https://docs.openclaw.ai/install/podman>
- 环境变量说明：<https://docs.openclaw.ai/help/environment>
- 反向代理安全说明：<https://docs.openclaw.ai/gateway/security/index#reverse-proxy-configuration>
- Slash Commands：<https://docs.openclaw.ai/tools/slash-commands#command-list>
- Multi-Agent Routing：<https://docs.openclaw.ai/concepts/multi-agent>
- Control UI：<https://docs.openclaw.ai/web/control-ui>
- Dashboard：<https://docs.openclaw.ai/web/dashboard>
- Devices CLI：<https://docs.openclaw.ai/cli/devices>
- ClawHub：<https://clawhub.ai/>

## 2. 镜像与启动脚本说明

`start-openclaw.sh` 的行为大致如下：

1. 检查本地是否已有 `localhost/local_openclaw:latest`
2. 如需更新则从 `OPENCLAW_IMAGE_URL` 拉取上游镜像并重新构建本地镜像
3. 初始化本地目录结构
4. 若不存在 `openclaw.json`，则自动生成最小可运行配置
5. 生成并写入 Gateway Token 或 Password 认证配置
6. 用 `podman run` 启动 `openclaw`
7. 生成 `systemd` 服务并注册自动拉起

默认镜像来源：

- `OPENCLAW_IMAGE_URL=${OPENCLAW_IMAGE_URL:-ghcr.io/openclaw/openclaw:latest}`

触发重新拉取/构建的条件：

- 本地镜像不存在
- 设置了 `OPENCLAW_UPDATE`
- 设置了 `ROUTER_IMAGE_UPDATE`

## 3. 目录映射与数据位置

脚本里会创建并挂载以下目录：

### 3.1 状态目录

- 宿主机：`$OPENCLAW_ETC_DIR`
- 容器内：`/openclaw/etc`

用途：

- `openclaw.json`
- `.env`
- `canvas/`
- `cron/`
- `devices/`
- 凭据、会话、状态文件

默认值：

- `OPENCLAW_ETC_DIR="$HOME/openclaw/etc"`

### 3.2 扩展目录

- 宿主机：`$OPENCLAW_EXTENSIONS_DIR`
- 容器内：`/openclaw/etc/extensions`

默认值：

- `OPENCLAW_EXTENSIONS_DIR="$OPENCLAW_ETC_DIR/extensions"`

### 3.3 共享技能目录

- 宿主机：`$OPENCLAW_SKILLS_DIR`
- 容器内：`/openclaw/skills`

默认值：

- `OPENCLAW_SHARED_COMPONENT_DIR="$HOME/openclaw/shared"`
- `OPENCLAW_SKILLS_DIR="$OPENCLAW_SHARED_COMPONENT_DIR/skills"`

脚本生成的配置里已经开启：

- `skills.load.extraDirs = ["/openclaw/skills"]`
- `skills.load.watch = true`

也就是说，把技能放到共享目录后，OpenClaw 会自动加载，并在后续会话中刷新可用技能列表。

### 3.4 工作区目录

- 宿主机：`$OPENCLAW_DATA_DIR`
- 容器内：`/openclaw/data`

默认值：

- `OPENCLAW_DATA_DIR="$HOME/openclaw/data"`

默认 agent 工作区：

- `/openclaw/data/default`

## 4. 默认端口与访问入口

默认端口：

- `OPENCLAW_PORT=18789`

启动完成后默认访问：

- `http://127.0.0.1:18789/`

脚本输出的信息包括：

- Control UI 地址
- 配置目录
- 扩展目录
- Workspace 目录

## 5. Gateway 认证与访问控制

### 5.1 Password 模式

如果设置了：

- `OPENCLAW_GATEWAY_PASSWORD`

脚本会把认证模式写入 `openclaw.json`：

- `gateway.auth.mode = "password"`
- `gateway.auth.password = "$OPENCLAW_GATEWAY_PASSWORD"`

也可以在容器内手工设置：

- `podman exec -it openclaw node openclaw.mjs config set gateway.auth.mode "password"`
- `podman exec -it openclaw node openclaw.mjs config set gateway.auth.password "your-strong-password"`

### 5.2 Token 模式

如果未设置 `OPENCLAW_GATEWAY_PASSWORD`，脚本会自动生成或读取：

- `openclaw.GATEWAY_TOKEN`
- `$OPENCLAW_ETC_DIR/.env` 中的 `OPENCLAW_GATEWAY_TOKEN`

随后把它传入容器环境变量。

### 5.3 Control UI 设备认证说明

需要注意：

- `dangerouslyDisableDeviceAuth: true` 会禁用设备配对认证
- 这是明显的安全降级，只建议在确定边界受控时使用

官方说明里还提到：

- 本地 `127.0.0.1` 访问通常可自动通过
- 远程浏览器首次连接 Control UI 时，可能需要用 `devices` 命令审批配对请求

常用设备审批命令：

- `openclaw devices list`
- `openclaw devices approve <requestId>`
- `openclaw devices approve --latest`
- `openclaw devices revoke --device <deviceId> --role <role>`

如果你当前是容器内方式运维，也可以进入容器执行相同的 `node openclaw.mjs ...` 子命令；不过官方文档通常使用宿主机上的 `openclaw` CLI 形式说明。

## 6. 环境变量

### 6.1 反向代理相关

- `OPENCLAW_ALLOWED_ORIGINS`
  - 逗号分隔的允许来源，例如：
  - `https://openclaw.example.com,https://other.example.com`
- `OPENCLAW_TRUSTED_PROXIES`
  - 逗号分隔的可信代理 IP / CIDR
  - 设置后 Gateway 会绑定到 loopback，并信任这些代理转发的头部
- `OPENCLAW_GATEWAY_PASSWORD`
  - 反向代理场景下建议启用 Password 模式

### 6.2 Provider / 模型相关

- `OPENCLAW_OPENAI_BASE_URL`
- `OPENCLAW_ZAI_BASE_URL`
- `OPENCLAW_LITELLM_BASE_URL`

这些变量会在首次初始化 `openclaw.json` 时写入 `models.providers`。

### 6.3 Provider API Keys

脚本支持以下常见 API Key 环境变量：

- `OPENCLAW_OPENROUTER_API_KEY`
- `OPENCLAW_ANTHROPIC_API_KEY`
- `OPENCLAW_OPENAI_API_KEY`
- `OPENCLAW_ZAI_API_KEY`
- `OPENCLAW_GROQ_API_KEY`
- `OPENCLAW_GOOGLE_API_KEY`
- `OPENCLAW_LITELLM_API_KEY`

传入容器时会映射为标准 provider 环境变量，例如：

- `OPENROUTER_API_KEY`
- `ANTHROPIC_API_KEY`
- `OPENAI_API_KEY`
- `ZAI_API_KEY`
- `GROQ_API_KEY`
- `GOOGLE_API_KEY`
- `LITELLM_API_KEY`

### 6.4 Channel Tokens

- `OPENCLAW_TELEGRAM_BOT_TOKEN`
- `OPENCLAW_DISCORD_BOT_TOKEN`

### 6.5 日志级别

- `OPENCLAW_LOG_LEVEL`
  - 可选值一般包括：`debug`、`info`、`warn`、`error`、`trace`

### 6.6 路径相关环境变量

脚本固定传入：

- `OPENCLAW_STATE_DIR=/openclaw/etc`
- `OPENCLAW_CONFIG_PATH=/openclaw/etc/openclaw.json`

官方还支持：

- `OPENCLAW_HOME`
- `OPENCLAW_STATE_DIR`
- `OPENCLAW_CONFIG_PATH`

优先级可参考官方环境变量文档。

## 7. 运行与服务管理

### 7.1 systemd 服务命令

如果脚本以普通用户运行，服务位于：

- `~/.config/systemd/user/openclaw.service`

如果脚本以 root 运行，服务位于：

- `/lib/systemd/system/openclaw.service`

常用命令：

- 启动：`systemctl [--user] start openclaw.service`
- 停止：`systemctl [--user] stop openclaw.service`
- 重启：`systemctl [--user] restart openclaw.service`
- 状态：`systemctl [--user] status openclaw.service`
- 日志：`journalctl [--user] -u openclaw.service -f`

### 7.2 Podman 容器命令

- 查看容器：`podman ps -a | grep openclaw`
- 查看日志：`podman logs -f openclaw`
- 停止容器：`podman stop openclaw`
- 删除容器：`podman rm -f openclaw`
- 进入容器：`podman exec -it openclaw bash`

### 7.3 常用诊断命令

- `podman exec openclaw node openclaw.mjs doctor`
- `podman exec openclaw node openclaw.mjs security audit`
- `podman exec openclaw node openclaw.mjs dashboard`
- `podman exec openclaw node openclaw.mjs dashboard --no-open`

## 8. Control UI / Dashboard 使用方法

### 8.1 本机访问

直接打开：

- `http://127.0.0.1:18789/`

如果 UI 提示未授权：

1. 确认 Gateway 正常运行
2. 使用 token 或 password 连接
3. 如是远程浏览器首次连接，按需审批设备配对

### 8.2 常见问题

- `unauthorized`
- `disconnected (1008): pairing required`

处理思路：

- 检查网关状态
- 检查 `gateway.auth.token` 或 `gateway.auth.password`
- 用 `devices list` 查看配对请求
- 用 `devices approve` 审批

### 8.3 Control UI 能做什么

根据官方文档，Control UI 目前可用于：

- 聊天与查看会话
- 查看和编辑配置
- 查看渠道状态
- 设备与节点管理
- skills 管理
- cron 管理
- exec 审批
- 调试、日志和健康检查

## 9. 容器内 CLI 常用命令

OpenClaw 容器中常见调用方式为：

- `podman exec -it openclaw node openclaw.mjs <subcommand>`

例如：

- `podman exec -it openclaw node openclaw.mjs onboard`
- `podman exec -it openclaw node openclaw.mjs doctor`
- `podman exec -it openclaw node openclaw.mjs security audit`
- `podman exec -it openclaw node openclaw.mjs dashboard --no-open`

## 10. 插件（Extensions）管理

### 10.1 常用命令

- `podman exec -it openclaw node openclaw.mjs plugins list`
- `podman exec -it openclaw node openclaw.mjs plugins install @openclaw/voice-call`
- `podman exec -it openclaw node openclaw.mjs plugins uninstall <id>`
- `podman exec -it openclaw node openclaw.mjs plugins enable <id>`
- `podman exec -it openclaw node openclaw.mjs plugins update --all`

### 10.2 插件配置位置

插件配置通常写入：

- `openclaw.json` 中的 `plugins.entries.<id>.config`

### 10.3 目录位置

插件安装目录映射为：

- 宿主机：`$OPENCLAW_EXTENSIONS_DIR`
- 容器内：`/openclaw/etc/extensions`

## 11. Reverse Proxy（Caddy）部署说明

参考文件：

- `openclaw.Caddyfile.location`

反向代理模式建议至少设置：

- `OPENCLAW_TRUSTED_PROXIES=127.0.0.1`
- `OPENCLAW_ALLOWED_ORIGINS=https://openclaw.example.com`
- `OPENCLAW_GATEWAY_PASSWORD=your-strong-password`

说明：

- Gateway 会绑定到 `loopback`
- 代理层负责 TLS 终止、HSTS 和 WebSocket Upgrade
- 生产环境应尽量避免直接把未认证的 Gateway 暴露到公网

补充安全建议：

- `OPENCLAW_ALLOWED_ORIGINS` 明确列出真实前端来源
- `OPENCLAW_TRUSTED_PROXIES` 仅信任必要的代理地址
- 尽量不要长期启用 `dangerouslyAllowHostHeaderOriginFallback`
- 更不要长期启用 `dangerouslyDisableDeviceAuth`

## 12. 模型认证与模型管理

### 12.1 交互式模型认证

- `podman exec -it openclaw node openclaw.mjs models auth add`

### 12.2 非交互式导入 API Key

OpenRouter：

- `podman exec -it openclaw node openclaw.mjs onboard --non-interactive --accept-risk --auth-choice openrouter-api-key --openrouter-api-key "sk-or-v1-..."`

OpenAI：

- `podman exec -it openclaw node openclaw.mjs onboard --non-interactive --accept-risk --auth-choice openai-api-key --openai-api-key "sk-..."`

LiteLLM：

- `podman exec -it openclaw node openclaw.mjs onboard --non-interactive --accept-risk --auth-choice litellm-api-key --litellm-api-key "sk-..."`

### 12.3 OAuth Token 相关

- `paste-token` 用于 OAuth / Session Token，不适合 API Key

常见命令：

- `podman exec -it openclaw node openclaw.mjs models auth paste-token --provider anthropic`
- `podman exec -it openclaw node openclaw.mjs models auth setup-token --provider anthropic`

### 12.4 设置默认模型

- `podman exec -it openclaw node openclaw.mjs models set "zai/glm-5"`
- `podman exec -it openclaw node openclaw.mjs config set agents.defaults.model '{"primary":"zai/glm-5","fallbacks":["openrouter/google/gemini-3.1-pro-preview","litellm/gemini-3.1-pro-preview","litellm/gpt-5.2","litellm/claude-sonnet-4.6","openrouter/openai/gpt-5.2"]}'`

### 12.5 模型扫描与状态查询

- `podman exec -it openclaw node openclaw.mjs models scan --provider openrouter`
- `podman exec -it openclaw node openclaw.mjs models scan --provider zai`
- `podman exec -it openclaw node openclaw.mjs models scan --provider litellm`
- `podman exec -it openclaw node openclaw.mjs models scan --provider openai`
- `podman exec -it openclaw node openclaw.mjs models list --all --provider openrouter`
- `podman exec -it openclaw node openclaw.mjs models status`

### 12.6 删除错误的 auth profile

- `podman exec -it openclaw node openclaw.mjs config unset auth.profiles.openai:manual`

## 13. Agent 管理命令

这一节是对脚本注释中 “添加 agent” 的补充。

### 13.1 OpenClaw 中 agent 的含义

一个 agent 通常包含：

- 独立 workspace
- 独立 `agentDir`
- 独立会话历史
- 独立认证资料（auth profiles）

官方建议：

- 不要复用不同 agent 的 `agentDir`
- 不同 agent 之间默认不会共享认证资料

### 13.2 当前脚本目录下的建议路径布局

脚本把工作目录挂到 `/openclaw/data`，因此给每个 agent 建议使用：

- `agentDir`：`/openclaw/data/<NAME>/agent`
- `workspace`：`/openclaw/data/<NAME>/workspace`

例如：

- `coding` agent
  - `agentDir=/openclaw/data/coding/agent`
  - `workspace=/openclaw/data/coding/workspace`

### 13.3 新增 agent

脚本注释中的新增方式：

- `podman exec -it openclaw node openclaw.mjs agents add --agent-dir /openclaw/data/NAME/agent --workspace /openclaw/data/NAME/workspace NAME`

官方简化写法（宿主机 CLI）：

- `openclaw agents add work`
- `openclaw agents add coding`

在容器部署场景中，更建议显式指定目录，避免默认路径落到容器临时位置。

### 13.4 查看 agent 列表

可以尝试：

- `podman exec -it openclaw node openclaw.mjs agents list`
- `podman exec -it openclaw node openclaw.mjs agents list --bindings`
- `podman exec -it openclaw node openclaw.mjs agents --help`

官方文档中常见等价命令：

- `openclaw agents list --bindings`

### 13.5 删除或调整 agent

不同版本 CLI 细节可能会有变化，建议先看帮助：

- `podman exec -it openclaw node openclaw.mjs agents --help`
- `podman exec -it openclaw node openclaw.mjs config --help`

一般来说，agent 的删改会涉及：

- `openclaw.json` 里的 `agents.list`
- `bindings`
- 对应工作区目录与 `agentDir`

### 13.6 修改默认模型

针对所有 agent 的默认模型：

- `podman exec -it openclaw node openclaw.mjs config set agents.defaults.model '{"primary":"bailian/glm-5"}'`

针对单个 agent，通常直接改配置更稳妥，例如在 `openclaw.json` 中为某个 agent 单独设置 `model`。

### 13.7 绑定 agent 到渠道 / 账号

多 agent 场景下，光创建 agent 还不够，还要通过 `bindings` 把渠道流量路由给它。

例如，按账号绑定：

- `main` 绑定 `feishu/default`
- `coding` 绑定 `feishu/coding`

当前目录下的 `etc/openclaw.json` 已经有类似配置示例：

- `agents.list` 中包含 `main` 和 `coding`
- `bindings` 把不同 `accountId` 路由到不同 agent

验证命令：

- `podman exec -it openclaw node openclaw.mjs agents list --bindings`

### 13.8 多 agent 的实用建议

- 每个 agent 使用单独的 `workspace`
- 每个 agent 使用单独的 `agentDir`
- 如果要做“编码 agent / 日常 agent / 公共 agent”分工，建议分别设置不同工具权限
- 若需要强隔离，配合 sandbox 使用

## 14. Slash Commands / 会话内常用命令

以下是适合在聊天界面里直接使用的命令：

- `/help`
- `/commands`
- `/status`
- `/whoami`
- `/agents`
- `/model <name>`
- `/reasoning on|off|stream`
- `/verbose on|full|off`
- `/elevated on|off|ask|full`
- `/exec host=<sandbox|gateway|node> security=<deny|allowlist|full> ask=<off|on-miss|always> node=<id>`
- `/config show|get|set|unset`
- `/debug show|set|unset|reset`
- `/restart`
- `/stop`

与 sub-agent / agent 协调相关的命令还有：

- `/subagents list|kill|log|info|send|steer|spawn`
- `/kill <id|#|all>`
- `/steer <id|#> <message>`
- `/tell <id|#> <message>`

说明：

- `/config` 默认是关闭的，需要 `commands.config=true`
- `/debug` 默认是关闭的，需要 `commands.debug=true`
- `/restart` 默认通常可用，但也可通过 `commands.restart=false` 禁用

## 15. LiteLLM 使用说明

### 15.1 环境变量

- `OPENCLAW_LITELLM_BASE_URL=http://litellm-host:4000`
- `OPENCLAW_LITELLM_API_KEY=sk-litellm-key`

### 15.2 同步 LiteLLM 模型列表

目录中已带脚本：

- `update-litellm-models.sh`

使用方式：

- `OPENCLAW_LITELLM_BASE_URL=http://litellm-host:4000 OPENCLAW_LITELLM_API_KEY=sk-litellm-key bash update-litellm-models.sh`

### 15.3 设置 LiteLLM 路由模型为默认模型

- `podman exec -it openclaw node openclaw.mjs models set "litellm/claude-opus-4-6"`

## 16. ClawHub 使用方法

ClawHub 是 OpenClaw 官方的技能仓库 / 技能市场，可用于：

- 浏览社区技能
- 搜索已有技能
- 一键安装 skill bundle
- 上传、导入和发布自己的 skill

官方入口：

- 首页：<https://clawhub.ai/>
- 技能列表：<https://clawhub.ai/skills?nonSuspicious=true>
- 搜索：<https://clawhub.ai/skills?focus=search>
- 上传：<https://clawhub.ai/upload>
- 导入：<https://clawhub.ai/import>

### 16.1 浏览技能

可以先从官方推荐或非可疑技能列表开始：

- `https://clawhub.ai/skills?nonSuspicious=true`

页面会显示：

- 技能名称
- 作者
- 下载量
- 星标数
- 版本数

适合先挑常用技能，例如：

- `find-skills`
- `github`
- `gog`
- `summarize`
- `weather`
- `obsidian`

### 16.2 安装技能

ClawHub 首页给出的安装方式是：

- `npx clawhub@latest install sonoscli`

如果你的环境里更偏向 `pnpm` / `bun`，也可以用相应的执行方式调用同一个安装器。

对于本目录的 Podman 部署，推荐把技能安装到宿主机的共享技能目录，也就是：

- `$OPENCLAW_SKILLS_DIR`

一个比较实用的流程是：

1. 先确认共享技能目录存在
2. 进入该目录
3. 用 `clawhub` 安装技能
4. 让 OpenClaw 自动加载或重启服务

例如：

- `cd "$OPENCLAW_SKILLS_DIR"`
- `npx clawhub@latest install github`

由于脚本生成的配置开启了 `skills.load.watch=true`，新技能通常会被自动发现；如果没有立即生效，可重启服务：

- `systemctl [--user] restart openclaw.service`

### 16.3 在 OpenClaw 中使用技能

安装成功后，技能通常会出现在以下位置之一：

- 宿主机共享技能目录：`$OPENCLAW_SKILLS_DIR`
- 容器内共享技能目录：`/openclaw/skills`

之后可以通过以下方式使用：

- 直接在聊天中让 agent 调用该 skill
- 使用 `/skill <name> [input]`
- 通过原始 prompt 让 agent 判断是否应该启用对应 skill

如果技能支持用户直接调用，`/skill <name>` 是最直观的入口。

### 16.4 上传 / 导入自己的技能

ClawHub 还支持：

- `Upload`：上传已有 skill bundle
- `Import`：导入并发布技能

根据站点页面，上传和导入通常需要 GitHub 登录。

适合的场景：

- 你在本地已经写好了技能，想发布给自己或团队复用
- 想把私有技能整理成可版本化的 bundle
- 想让多个 OpenClaw 实例复用同一套 skill

### 16.5 使用建议

- 优先选择下载量高、星标高、标记为非可疑的技能
- 安装后先检查 skill 内容和依赖
- 对涉及外部 API 的 skill，按文档补齐环境变量或密钥
- 对高权限 skill，建议配合 agent 沙箱与工具白名单一起使用

## 17. 安全建议

- 尽量避免把 Gateway 未认证地暴露到公网
- 优先使用 localhost、SSH 隧道、Tailscale Serve 或反向代理 + Password/Token
- 明确设置 `OPENCLAW_ALLOWED_ORIGINS`
- 限制 `OPENCLAW_TRUSTED_PROXIES`
- 定期执行：`podman exec openclaw node openclaw.mjs security audit`
- 对多用户/多来源消息场景，优先使用多 agent + 最小权限原则
- 对公共或低信任 agent，限制 `exec`、`write`、`apply_patch`、`browser` 等高风险工具

## 18. 一个推荐的运维顺序

1. 运行 `start-openclaw.sh`
2. 打开 `http://127.0.0.1:18789/`
3. 完成 Dashboard 登录 / 配对
4. 配置模型认证
5. 按需安装插件与技能
6. 新建 agent 并配置 `bindings`
7. 若走公网入口，配置 Caddy 反向代理与密码认证
8. 执行 `security audit` 做一次基线检查

## 19. 速查命令清单

### 服务管理

- `systemctl [--user] start openclaw.service`
- `systemctl [--user] stop openclaw.service`
- `systemctl [--user] restart openclaw.service`
- `journalctl [--user] -u openclaw.service -f`

### 容器管理

- `podman logs -f openclaw`
- `podman exec -it openclaw bash`
- `podman exec -it openclaw node openclaw.mjs doctor`
- `podman exec -it openclaw node openclaw.mjs security audit`

### agent 管理

- `podman exec -it openclaw node openclaw.mjs agents add --agent-dir /openclaw/data/NAME/agent --workspace /openclaw/data/NAME/workspace NAME`
- `podman exec -it openclaw node openclaw.mjs agents list --bindings`
- `podman exec -it openclaw node openclaw.mjs agents --help`

### plugin 管理

- `podman exec -it openclaw node openclaw.mjs plugins list`
- `podman exec -it openclaw node openclaw.mjs plugins install <npm-spec>`
- `podman exec -it openclaw node openclaw.mjs plugins update --all`

### model 管理

- `podman exec -it openclaw node openclaw.mjs models auth add`
- `podman exec -it openclaw node openclaw.mjs models scan --provider openrouter`
- `podman exec -it openclaw node openclaw.mjs models status`
- `podman exec -it openclaw node openclaw.mjs models set "openrouter/anthropic/claude-sonnet-4"`

### skills / ClawHub

- `cd "$OPENCLAW_SKILLS_DIR"`
- `npx clawhub@latest install github`
- `/skill github`
