#!/bin/bash

set -euo pipefail
shopt -s extglob

# Simple SmartDNS geosite importer.
# Example:
#   bash smartdns-generate-geosite.sh \
#     --name proxy-github \
#     --geosite-dir geosite \
#     --source geosite-github \
#     --source geosite-docker \
#     --domain api.github.com \
#     --domain-suffix github.com \
#     --domain-regex '^github-production-release-asset-[0-9a-zA-Z]{6}\\.s3\\.amazonaws\\.com$' \
#     --dns-group proxy_dns \
#     --disable-ipv6 \
#     --nftset4 inet#sdwan#PROXY_FAST_IPV4 \
#     --nftset6 inet#sdwan#PROXY_FAST_IPV6
# Bridge traffic can be lifted into inet/ip rules by setup-router/sdwan/setup-sdwan-route.sh via meta broute set 1.

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
source "$(dirname "$SCRIPT_DIR")/configure-router.sh"

SMARTDNS_ETC_DIR="${SMARTDNS_ETC_DIR:-$SCRIPT_DIR/smartdns-etc}"
GENERATED_DIR="${SMARTDNS_ETC_DIR}/generated.d"
GEOSITE_DIR="$SCRIPT_DIR/geosite"
OUTPUT_NAME="geosite-import"
DNS_GROUP=""
SPEED_CHECK_MODE="none"
DISABLE_IPV6=0
declare -a GEOSITE_SOURCES=()
declare -a CUSTOM_DOMAINS=()
declare -a CUSTOM_DOMAIN_SUFFIXES=()
declare -a CUSTOM_DOMAIN_REGEXES=()
declare -a NFTSET_IPV4=()
declare -a NFTSET_IPV6=()

function progress() {
  echo "[smartdns-geosite] $*" >&2
}

function usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --name NAME                 Output name, used for generated .conf/.list files.
  --geosite-dir DIR           Directory containing sing-box geosite json files.
  --generated-dir DIR         Output directory, default: $GENERATED_DIR
  --source NAME_OR_FILE       Repeatable. Example: geosite-github
  --domain DOMAIN             Repeatable exact/full domain. Example: api.github.com
  --domain-suffix DOMAIN      Repeatable domain suffix. Example: github.com
  --domain-regex REGEX        Repeatable domain regex. Only simple exact regex can be converted.
  --dns-group GROUP           SmartDNS upstream group, for example: proxy_dns
  --speed-check-mode MODE     SmartDNS speed-check-mode, default: none
  --disable-ipv6              Add '-address #6' to disable AAAA answers.
  --nftset4 FAMILY#TABLE#SET  Repeatable IPv4 nftset target.
  --nftset6 FAMILY#TABLE#SET  Repeatable IPv6 nftset target.
  -h, --help                  Show this help.

Notes:
  - Generated files are written to generated.d only.
  - You may use custom domain options without any --source.
  - SmartDNS currently supports one nftset per address family. Extra nftsets are kept as comments.
  - domain_regex only supports simple exact patterns such as '^api\\.example\\.com$'.
EOF
}

function normalize_domain() {
  local domain="${1,,}"
  domain="${domain##+([[:space:]])}"
  domain="${domain%%+([[:space:]])}"
  while [[ "$domain" == .* ]]; do
    domain="${domain#.}"
  done
  while [[ "$domain" == *. ]]; do
    domain="${domain%.}"
  done
  printf '%s\n' "$domain"
}

function sanitize_file_component() {
  local value="${1,,}"
  value="${value//[^a-z0-9._-]/-}"
  value="$(printf '%s' "$value" | sed -E 's/-+/-/g; s/^-+//; s/-+$//')"
  if [[ -z "$value" ]]; then
    value="geosite-import"
  fi
  printf '%s\n' "$value"
}

function sanitize_symbol() {
  local value="$1"
  value="${value//[^a-zA-Z0-9_]/_}"
  value="$(printf '%s' "$value" | sed -E 's/_+/_/g; s/^_+//; s/_+$//')"
  if [[ -z "$value" ]]; then
    value="geosite_import"
  fi
  printf '%s\n' "$value"
}

function resolve_from_script_dir() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s\n' "$SCRIPT_DIR/$path"
  fi
}

function resolve_geosite_json() {
  local item="$1"
  local base_dir="$2"
  local candidate=""

  if [[ "$item" == /* ]]; then
    candidate="$item"
  elif [[ -e "$base_dir/$item" ]]; then
    candidate="$base_dir/$item"
  elif [[ -e "$base_dir/$item.srs.json" ]]; then
    candidate="$base_dir/$item.srs.json"
  elif [[ -e "$base_dir/$item.json" ]]; then
    candidate="$base_dir/$item.json"
  fi

  if [[ -z "$candidate" ]] || [[ ! -e "$candidate" ]]; then
    echo "Error: geosite json not found for '$item' under '$base_dir'." >&2
    exit 1
  fi

  readlink -f "$candidate"
}

function convert_regex_to_exact_domain() {
  local regex="$1"
  if [[ "$regex" =~ ^\^([A-Za-z0-9_-]+(\\\.[A-Za-z0-9_-]+)*)\$$ ]]; then
    printf '%s\n' "$(normalize_domain "${BASH_REMATCH[1]//\\./.}")"
    return 0
  fi
  return 1
}

function add_entry() {
  local entry_kind="$1"
  local entry_value="$2"

  if [[ -z "${entry_value:-}" ]] || [[ "$entry_value" == "null" ]]; then
    return 0
  fi

  case "$entry_kind" in
    domain)
      entry_value="$(normalize_domain "$entry_value")"
      [[ -n "$entry_value" ]] && EXACT_DOMAINS[$entry_value]=1
      ;;
    suffix)
      entry_value="$(normalize_domain "$entry_value")"
      [[ -n "$entry_value" ]] && SUFFIX_DOMAINS[$entry_value]=1
      ;;
    regex)
      if converted_domain="$(convert_regex_to_exact_domain "$entry_value")"; then
        [[ -n "$converted_domain" ]] && EXACT_DOMAINS[$converted_domain]=1
      else
        UNSUPPORTED_REGEX[$entry_value]=1
      fi
      ;;
    keyword)
      UNSUPPORTED_KEYWORD[$entry_value]=1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      OUTPUT_NAME="$2"
      shift 2
      ;;
    --geosite-dir)
      GEOSITE_DIR="$2"
      shift 2
      ;;
    --generated-dir)
      GENERATED_DIR="$2"
      shift 2
      ;;
    --source)
      GEOSITE_SOURCES+=("$2")
      shift 2
      ;;
    --domain)
      CUSTOM_DOMAINS+=("$2")
      shift 2
      ;;
    --domain-suffix)
      CUSTOM_DOMAIN_SUFFIXES+=("$2")
      shift 2
      ;;
    --domain-regex)
      CUSTOM_DOMAIN_REGEXES+=("$2")
      shift 2
      ;;
    --dns-group)
      DNS_GROUP="$2"
      shift 2
      ;;
    --speed-check-mode)
      SPEED_CHECK_MODE="$2"
      shift 2
      ;;
    --disable-ipv6)
      DISABLE_IPV6=1
      shift
      ;;
    --nftset4)
      NFTSET_IPV4+=("$2")
      shift 2
      ;;
    --nftset6)
      NFTSET_IPV6+=("$2")
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ ${#GEOSITE_SOURCES[@]} -eq 0 ]] && [[ ${#CUSTOM_DOMAINS[@]} -eq 0 ]] && [[ ${#CUSTOM_DOMAIN_SUFFIXES[@]} -eq 0 ]] && [[ ${#CUSTOM_DOMAIN_REGEXES[@]} -eq 0 ]]; then
  echo "Error: at least one --source, --domain, --domain-suffix or --domain-regex is required." >&2
  usage >&2
  exit 1
fi

if [[ ${#GEOSITE_SOURCES[@]} -gt 0 ]] && ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required." >&2
  exit 1
fi

GEOSITE_DIR="$(resolve_from_script_dir "$GEOSITE_DIR")"
GENERATED_DIR="$(resolve_from_script_dir "$GENERATED_DIR")"
mkdir -p "$GENERATED_DIR"

declare -A EXACT_DOMAINS=()
declare -A SUFFIX_DOMAINS=()
declare -A UNSUPPORTED_REGEX=()
declare -A UNSUPPORTED_KEYWORD=()
declare -a RESOLVED_SOURCES=()

progress "start name=$OUTPUT_NAME source=${#GEOSITE_SOURCES[@]} custom-domain=${#CUSTOM_DOMAINS[@]} custom-suffix=${#CUSTOM_DOMAIN_SUFFIXES[@]} custom-regex=${#CUSTOM_DOMAIN_REGEXES[@]}"

for custom_domain in "${CUSTOM_DOMAINS[@]}"; do
  add_entry domain "$custom_domain"
done

for custom_suffix in "${CUSTOM_DOMAIN_SUFFIXES[@]}"; do
  add_entry suffix "$custom_suffix"
done

for custom_regex in "${CUSTOM_DOMAIN_REGEXES[@]}"; do
  add_entry regex "$custom_regex"
done

if [[ ${#CUSTOM_DOMAINS[@]} -gt 0 ]] || [[ ${#CUSTOM_DOMAIN_SUFFIXES[@]} -gt 0 ]] || [[ ${#CUSTOM_DOMAIN_REGEXES[@]} -gt 0 ]]; then
  progress "loaded custom inputs"
fi

for source_index in "${!GEOSITE_SOURCES[@]}"; do
  source_item="${GEOSITE_SOURCES[$source_index]}"
  progress "[$((source_index + 1))/${#GEOSITE_SOURCES[@]}] loading $source_item"
  source_json="$(resolve_geosite_json "$source_item" "$GEOSITE_DIR")"
  RESOLVED_SOURCES+=("$source_json")
  source_entry_count=0

  while IFS=$'\t' read -r entry_kind entry_value; do
    add_entry "$entry_kind" "$entry_value"
    source_entry_count=$((source_entry_count + 1))
  done < <(
    jq -r '
      def emit($kind; $value):
        if $value == null then empty
        elif ($value | type) == "array" then $value[] | "\($kind)\t\(.)"
        else "\($kind)\t\($value)"
        end;
      .rules[]? |
        emit("domain"; .domain),
        emit("suffix"; .domain_suffix),
        emit("regex"; .domain_regex),
        emit("keyword"; .domain_keyword)
    ' "$source_json"
  )

  progress "[$((source_index + 1))/${#GEOSITE_SOURCES[@]}] parsed $source_entry_count entries from $(basename "$source_json")"
done

raw_suffix_count=${#SUFFIX_DOMAINS[@]}
raw_exact_count=${#EXACT_DOMAINS[@]}
progress "normalizing and removing redundant domains (suffix=$raw_suffix_count exact=$raw_exact_count)"

declare -A KEPT_SUFFIX_DOMAINS=()
for suffix_domain in "${!SUFFIX_DOMAINS[@]}"; do
  suffix_redundant=0
  parent_suffix="$suffix_domain"
  while [[ "$parent_suffix" == *.* ]]; do
    parent_suffix="${parent_suffix#*.}"
    if [[ -n "${SUFFIX_DOMAINS[$parent_suffix]+x}" ]]; then
      suffix_redundant=1
      break
    fi
  done
  [[ $suffix_redundant -eq 0 ]] && KEPT_SUFFIX_DOMAINS[$suffix_domain]=1
done

declare -A KEPT_EXACT_DOMAINS=()
for exact_domain in "${!EXACT_DOMAINS[@]}"; do
  exact_redundant=0
  if [[ -n "${KEPT_SUFFIX_DOMAINS[$exact_domain]+x}" ]]; then
    exact_redundant=1
  else
    parent_domain="$exact_domain"
    while [[ "$parent_domain" == *.* ]]; do
      parent_domain="${parent_domain#*.}"
      if [[ -n "${KEPT_SUFFIX_DOMAINS[$parent_domain]+x}" ]]; then
        exact_redundant=1
        break
      fi
    done
  fi
  [[ $exact_redundant -eq 0 ]] && KEPT_EXACT_DOMAINS[$exact_domain]=1
done

OUTPUT_SLUG="$(sanitize_file_component "$OUTPUT_NAME")"
DOMAIN_SET_NAME="$(sanitize_symbol "geosite_${OUTPUT_SLUG}")"
LIST_FILE="$GENERATED_DIR/60-${OUTPUT_SLUG}.list"
CONF_FILE="$GENERATED_DIR/60-${OUTPUT_SLUG}.conf"
LIST_BASENAME="$(basename "$LIST_FILE")"
SUPPORTED_SUFFIX_COUNT=${#KEPT_SUFFIX_DOMAINS[@]}
SUPPORTED_EXACT_COUNT=${#KEPT_EXACT_DOMAINS[@]}
SUPPORTED_DOMAIN_COUNT=$((SUPPORTED_SUFFIX_COUNT + SUPPORTED_EXACT_COUNT))

progress "deduplicated result suffix=$SUPPORTED_SUFFIX_COUNT exact=$SUPPORTED_EXACT_COUNT unsupported-regex=${#UNSUPPORTED_REGEX[@]} unsupported-keyword=${#UNSUPPORTED_KEYWORD[@]}"

NFTSET_VALUE=""
if [[ ${#NFTSET_IPV4[@]} -gt 0 ]]; then
  NFTSET_VALUE="#4:${NFTSET_IPV4[0]}"
fi
if [[ ${#NFTSET_IPV6[@]} -gt 0 ]]; then
  if [[ -n "$NFTSET_VALUE" ]]; then
    NFTSET_VALUE+=","
  fi
  NFTSET_VALUE+="#6:${NFTSET_IPV6[0]}"
fi

rm -f "$LIST_FILE"
if [[ $SUPPORTED_DOMAIN_COUNT -gt 0 ]]; then
  progress "writing list file $(basename "$LIST_FILE")"
  {
    echo "# Generated by $(basename "$0")"
    if [[ ${#RESOLVED_SOURCES[@]} -gt 0 ]]; then
      for source_json in "${RESOLVED_SOURCES[@]}"; do
        echo "# $source_json"
      done
    else
      echo "# custom-input-only"
    fi
    if [[ ${#CUSTOM_DOMAINS[@]} -gt 0 ]] || [[ ${#CUSTOM_DOMAIN_SUFFIXES[@]} -gt 0 ]] || [[ ${#CUSTOM_DOMAIN_REGEXES[@]} -gt 0 ]]; then
      echo "# custom domain=${#CUSTOM_DOMAINS[@]} suffix=${#CUSTOM_DOMAIN_SUFFIXES[@]} regex=${#CUSTOM_DOMAIN_REGEXES[@]}"
    fi
    if [[ $SUPPORTED_SUFFIX_COUNT -gt 0 ]]; then
      printf '%s\n' "${!KEPT_SUFFIX_DOMAINS[@]}" | sort
    fi
    if [[ $SUPPORTED_EXACT_COUNT -gt 0 ]]; then
      printf '%s\n' "${!KEPT_EXACT_DOMAINS[@]}" | sort | sed 's/^/-./'
    fi
  } >"$LIST_FILE"
fi

progress "writing config file $(basename "$CONF_FILE")"
{
  echo "# Generated by $(basename "$0")"
  echo "# Sources:"
  if [[ ${#RESOLVED_SOURCES[@]} -gt 0 ]]; then
    for source_json in "${RESOLVED_SOURCES[@]}"; do
      echo "#   $source_json"
    done
  else
    echo "#   custom-input-only"
  fi
  if [[ ${#CUSTOM_DOMAINS[@]} -gt 0 ]] || [[ ${#CUSTOM_DOMAIN_SUFFIXES[@]} -gt 0 ]] || [[ ${#CUSTOM_DOMAIN_REGEXES[@]} -gt 0 ]]; then
    echo "# Custom inputs: domain=${#CUSTOM_DOMAINS[@]}, suffix=${#CUSTOM_DOMAIN_SUFFIXES[@]}, regex=${#CUSTOM_DOMAIN_REGEXES[@]}"
  fi
  echo "# Supported domains: ${SUPPORTED_DOMAIN_COUNT} (suffix=${SUPPORTED_SUFFIX_COUNT}, exact=${SUPPORTED_EXACT_COUNT})"
  echo

  if [[ $SUPPORTED_DOMAIN_COUNT -gt 0 ]]; then
    echo "domain-set -name $DOMAIN_SET_NAME -file /etc/smartdns/generated.d/$LIST_BASENAME"
    if [[ -n "$NFTSET_VALUE" ]]; then
      echo "nftset-timeout yes"
    fi

    DOMAIN_RULE_LINE="domain-rules /domain-set:${DOMAIN_SET_NAME}/"
    [[ -n "$SPEED_CHECK_MODE" ]] && DOMAIN_RULE_LINE+=" -speed-check-mode $SPEED_CHECK_MODE"
    [[ -n "$DNS_GROUP" ]] && DOMAIN_RULE_LINE+=" -nameserver $DNS_GROUP"
    [[ $DISABLE_IPV6 -ne 0 ]] && DOMAIN_RULE_LINE+=" -address #6"
    [[ -n "$NFTSET_VALUE" ]] && DOMAIN_RULE_LINE+=" -nftset $NFTSET_VALUE"
    echo "$DOMAIN_RULE_LINE"
  else
    echo "# No SmartDNS-compatible domain or domain_suffix entries were generated."
  fi

  if [[ ${#NFTSET_IPV4[@]} -gt 1 ]] || [[ ${#NFTSET_IPV6[@]} -gt 1 ]] || [[ ${#UNSUPPORTED_REGEX[@]} -gt 0 ]] || [[ ${#UNSUPPORTED_KEYWORD[@]} -gt 0 ]]; then
    echo
    echo "# Notes:"
    if [[ ${#NFTSET_IPV4[@]} -gt 1 ]]; then
      echo "#   Additional IPv4 nftsets were ignored by SmartDNS: ${NFTSET_IPV4[*]:1}"
    fi
    if [[ ${#NFTSET_IPV6[@]} -gt 1 ]]; then
      echo "#   Additional IPv6 nftsets were ignored by SmartDNS: ${NFTSET_IPV6[*]:1}"
    fi
    if [[ ${#UNSUPPORTED_REGEX[@]} -gt 0 ]]; then
      echo "#   Unsupported domain_regex entries:"
      printf '%s\n' "${!UNSUPPORTED_REGEX[@]}" | sort | sed 's/^/#     /'
    fi
    if [[ ${#UNSUPPORTED_KEYWORD[@]} -gt 0 ]]; then
      echo "#   Unsupported domain_keyword entries:"
      printf '%s\n' "${!UNSUPPORTED_KEYWORD[@]}" | sort | sed 's/^/#     /'
    fi
  fi
} >"$CONF_FILE"

progress "done supported=$SUPPORTED_DOMAIN_COUNT list=$(basename "$LIST_FILE") conf=$(basename "$CONF_FILE")"
echo "Generated: $CONF_FILE" >&2
if [[ -e "$LIST_FILE" ]]; then
  echo "Generated: $LIST_FILE" >&2
fi