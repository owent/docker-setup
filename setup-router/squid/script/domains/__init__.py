# 域名配置模块
from .github import GITHUB_DOMAINS
from .cdn import CDN_DOMAINS
from .microsoft import MICROSOFT_DOMAINS
from .unreal_engine import UNREAL_ENGINE_DOMAINS
from .unity import UNITY_DOMAINS

# 合并所有域名模式
ALL_PATTERNS = (GITHUB_DOMAINS + CDN_DOMAINS + MICROSOFT_DOMAINS +
                UNREAL_ENGINE_DOMAINS + UNITY_DOMAINS)
