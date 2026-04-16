#!/usr/bin/env python3
# pylint: disable=invalid-name
"""Simple SmartDNS geosite importer."""

from __future__ import annotations

import json
import os
import re
import sys
from collections.abc import Iterable, Iterator
from dataclasses import dataclass, field
from pathlib import Path

SCRIPT_PATH = Path(__file__).resolve()
SCRIPT_DIR = SCRIPT_PATH.parent
CONFIGURE_ROUTER_PATH = SCRIPT_DIR.parent / "configure-router.sh"
WINDOWS_DRIVE_PATTERN = re.compile(r"^[A-Za-z]:[\\/]")
MSYS_DRIVE_PATTERN = re.compile(r"^/([A-Za-z])/(.*)$")
SHELL_ASSIGNMENT_PATTERN = re.compile(r"^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$")
SHELL_VARIABLE_PATTERN = re.compile(r"\$(?:{([A-Za-z_][A-Za-z0-9_]*)}|([A-Za-z_][A-Za-z0-9_]*))")
EXACT_DOMAIN_REGEX_PATTERN = re.compile(r"^\^([A-Za-z0-9_-]+(?:\\\.[A-Za-z0-9_-]+)*)\$$")
FILE_COMPONENT_SANITIZE_PATTERN = re.compile(r"[^a-z0-9._-]")
SYMBOL_SANITIZE_PATTERN = re.compile(r"[^a-zA-Z0-9_]")
MULTI_HYPHEN_PATTERN = re.compile(r"-+")
MULTI_UNDERSCORE_PATTERN = re.compile(r"_+")


class UsageRequested(Exception):
    """Raised when the user requests usage output."""


class CommandLineError(Exception):
    """Raised when the command-line arguments are invalid."""


# pylint: disable=too-few-public-methods,too-many-instance-attributes
@dataclass
class Options:
    """Command-line options for the SmartDNS geosite generator."""

    output_name: str = "geosite-import"
    geosite_dir: str = "geosite"
    generated_dir: str | None = None
    sources: list[str] = field(default_factory=list)
    custom_domains: list[str] = field(default_factory=list)
    custom_domain_suffixes: list[str] = field(default_factory=list)
    custom_domain_regexes: list[str] = field(default_factory=list)
    exclude_domains: list[str] = field(default_factory=list)
    exclude_domain_suffixes: list[str] = field(default_factory=list)
    exclude_domain_regexes: list[str] = field(default_factory=list)
    dns_group: str = ""
    speed_check_mode: str = "none"
    disable_ipv6: bool = False
    nftset_ipv4: list[str] = field(default_factory=list)
    nftset_ipv6: list[str] = field(default_factory=list)


# pylint: disable=too-few-public-methods
@dataclass
class EntryState:
    """Merged geosite entries before final rendering."""

    exact_domains: set[str] = field(default_factory=set)
    suffix_domains: set[str] = field(default_factory=set)
    unsupported_regex: set[str] = field(default_factory=set)
    unsupported_keyword: set[str] = field(default_factory=set)


# pylint: disable=too-few-public-methods
@dataclass
class ExclusionState:
    """Compiled exclusion rules applied after deduplication."""

    exact_domains: set[str] = field(default_factory=set)
    suffix_domains: set[str] = field(default_factory=set)
    regex_patterns: list[str] = field(default_factory=list)
    compiled_regexes: list[re.Pattern[str]] = field(default_factory=list)
    invalid_regex: set[str] = field(default_factory=set)
    unapplied_exact_excludes: set[str] = field(default_factory=set)


# pylint: disable=too-few-public-methods
@dataclass
class GeneratedDomains:
    """Deduplicated and filtered domains ready for rendering."""

    suffix_domains: set[str]
    exact_domains: set[str]
    dedup_suffix_count: int
    dedup_exact_count: int
    excluded_suffix_count: int = 0
    excluded_exact_count: int = 0


# pylint: disable=too-few-public-methods
@dataclass(frozen=True)
class RenderTargets:
    """Resolved output file locations and derived names."""

    output_slug: str
    domain_set_name: str
    list_file: Path
    conf_file: Path
    list_basename: str
    nftset_value: str


# pylint: disable=too-few-public-methods
@dataclass(frozen=True)
class GenerationContext:
    """All data needed to render the SmartDNS output files."""

    options: Options
    resolved_sources: tuple[Path, ...]
    entries: EntryState
    exclusions: ExclusionState
    domains: GeneratedDomains
    targets: RenderTargets


VALUE_OPTIONS = {
    "--name": "output_name",
    "--geosite-dir": "geosite_dir",
    "--generated-dir": "generated_dir",
    "--dns-group": "dns_group",
    "--speed-check-mode": "speed_check_mode",
}

LIST_OPTIONS = {
    "--source": "sources",
    "--domain": "custom_domains",
    "--domain-suffix": "custom_domain_suffixes",
    "--domain-regex": "custom_domain_regexes",
    "--exclude-domain": "exclude_domains",
    "--exclude-domain-suffix": "exclude_domain_suffixes",
    "--exclude-domain-regex": "exclude_domain_regexes",
    "--nftset4": "nftset_ipv4",
    "--nftset6": "nftset_ipv6",
}


def current_script_name() -> str:
    """Return the basename used to invoke this script."""

    if sys.argv and sys.argv[0]:
        return Path(sys.argv[0]).name
    return SCRIPT_PATH.name


def progress(message: str) -> None:
    """Write a progress message to stderr."""

    print(f"[smartdns-geosite] {message}", file=sys.stderr)


def format_usage(default_generated_dir: Path) -> str:
    """Build the usage text shown for help and argument errors."""

    script_name = current_script_name()
    return "\n".join(
        [
            f"Usage: {script_name} [options]",
            "",
            "Options:",
            "  --name NAME                 Output name, used for generated .conf/.list files.",
            "  --geosite-dir DIR           Directory containing sing-box geosite json files.",
            f"  --generated-dir DIR         Output directory, default: {default_generated_dir}",
            "  --source NAME_OR_FILE       Repeatable. Example: geosite-github",
            "  --domain DOMAIN             Repeatable exact/full domain. Example: api.github.com",
            "  --domain-suffix DOMAIN      Repeatable domain suffix. Example: github.com",
            (
                "  --domain-regex REGEX        Repeatable domain regex. "
                "Only simple exact regex can be converted."
            ),
            "  --exclude-domain DOMAIN     Repeatable exact/full domain to remove after merge.",
            (
                "  --exclude-domain-suffix D   Repeatable domain suffix subtree "
                "to remove after merge."
            ),
            (
                "  --exclude-domain-regex RE   Repeatable regex applied to merged "
                "result entry names after merge."
            ),
            "  --dns-group GROUP           SmartDNS upstream group, for example: proxy_dns",
            "  --speed-check-mode MODE     SmartDNS speed-check-mode, default: none",
            "  --disable-ipv6              Add '-address #6' to disable AAAA answers.",
            "  --nftset4 FAMILY#TABLE#SET  Repeatable IPv4 nftset target.",
            "  --nftset6 FAMILY#TABLE#SET  Repeatable IPv6 nftset target.",
            "  -h, --help                  Show this help.",
            "",
            "Notes:",
            "  - Generated files are written to generated.d only.",
            "  - You may use custom domain options without any --source.",
            "  - Exclusions are applied after merge/dedup and before writing output.",
            (
                "  - SmartDNS currently supports one nftset per address family. "
                "Extra nftsets are kept as comments."
            ),
            (
                "  - domain_regex only supports simple exact patterns such as "
                "'^api\\.example\\.com$'."
            ),
            "  - exclude-domain-regex uses extended regular expression syntax.",
            (
                "  - exclude-domain cannot carve a hole out of a broader kept suffix; "
                "use exclude-domain-suffix on the parent suffix when needed."
            ),
        ]
    )


def require_option_value(arguments: list[str], index: int) -> str:
    """Return the value following an option or raise an argument error."""

    if index + 1 >= len(arguments):
        raise CommandLineError(f"Error: option requires a value: {arguments[index]}")
    return arguments[index + 1]


def parse_arguments(arguments: list[str]) -> Options:
    """Parse command-line arguments while preserving the legacy interface."""

    options = Options()
    index = 0
    while index < len(arguments):
        argument = arguments[index]
        if argument in {"-h", "--help"}:
            raise UsageRequested()

        if argument == "--disable-ipv6":
            options.disable_ipv6 = True
            index += 1
            continue

        if argument in VALUE_OPTIONS:
            setattr(options, VALUE_OPTIONS[argument], require_option_value(arguments, index))
            index += 2
            continue

        if argument in LIST_OPTIONS:
            getattr(options, LIST_OPTIONS[argument]).append(require_option_value(arguments, index))
            index += 2
            continue

        raise CommandLineError(f"Error: unknown option: {argument}")

    return options


def normalize_domain(domain: str) -> str:
    """Normalize a domain name the same way as the legacy Bash script."""

    return domain.lower().strip().strip(".")


def sanitize_file_component(value: str) -> str:
    """Convert an arbitrary value to a safe file-name component."""

    sanitized = FILE_COMPONENT_SANITIZE_PATTERN.sub("-", value.lower())
    sanitized = MULTI_HYPHEN_PATTERN.sub("-", sanitized).strip("-")
    return sanitized or "geosite-import"


def sanitize_symbol(value: str) -> str:
    """Convert an arbitrary value to a safe SmartDNS symbol name."""

    sanitized = SYMBOL_SANITIZE_PATTERN.sub("_", value)
    sanitized = MULTI_UNDERSCORE_PATTERN.sub("_", sanitized).strip("_")
    return sanitized or "geosite_import"


def to_platform_path(path_text: str) -> Path:
    """Convert MSYS-style absolute paths to native paths on Windows."""

    if os.name == "nt":
        msys_match = MSYS_DRIVE_PATTERN.match(path_text)
        if msys_match:
            return Path(f"{msys_match.group(1)}:/{msys_match.group(2)}")
    return Path(path_text)


def is_absolute_path(path_text: str) -> bool:
    """Return whether a path should be treated as absolute."""

    return path_text.startswith(("/", "\\")) or bool(WINDOWS_DRIVE_PATTERN.match(path_text))


def resolve_from_script_dir(path_text: str) -> Path:
    """Resolve a path relative to the current script directory."""

    candidate = to_platform_path(path_text)
    if is_absolute_path(path_text):
        return candidate.resolve(strict=False)
    return (SCRIPT_DIR / candidate).resolve(strict=False)


def expand_shell_variables(value: str, known_values: dict[str, str]) -> str:
    """Expand simple shell variable references from already known scalar values."""

    def replace(match: re.Match[str]) -> str:
        variable_name = match.group(1) or match.group(2) or ""
        return known_values.get(variable_name, "")

    return SHELL_VARIABLE_PATTERN.sub(replace, value)


def parse_shell_assignment_value(raw_value: str, known_values: dict[str, str]) -> str | None:
    """Parse a simple shell assignment value without executing shell code."""

    value = raw_value.strip()
    if value.startswith("(") or "$(" in value or "`" in value:
        return None

    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        value = value[1:-1]

    return expand_shell_variables(value, known_values)


def load_default_smartdns_etc_dir() -> Path:
    """Read the default SmartDNS config directory from configure-router.sh."""

    known_values: dict[str, str] = {}
    if CONFIGURE_ROUTER_PATH.is_file():
        for line in CONFIGURE_ROUTER_PATH.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue

            match = SHELL_ASSIGNMENT_PATTERN.match(stripped)
            if not match:
                continue

            variable_name, raw_value = match.groups()
            if variable_name not in {"ROUTER_HOME", "SMARTDNS_ETC_DIR"}:
                continue

            parsed_value = parse_shell_assignment_value(raw_value, known_values)
            if parsed_value is not None:
                known_values[variable_name] = parsed_value

    configured_path = known_values.get("SMARTDNS_ETC_DIR")
    if configured_path:
        return to_platform_path(configured_path).resolve(strict=False)
    return (SCRIPT_DIR / "smartdns-etc").resolve(strict=False)


def resolve_geosite_json(item: str, base_dir: Path) -> Path:
    """Resolve a geosite source name or path to an existing JSON file."""

    candidate_paths: list[Path] = []
    item_path = to_platform_path(item)
    if is_absolute_path(item):
        candidate_paths.append(item_path)
    else:
        candidate_paths.extend(
            [
                base_dir / item_path,
                base_dir / f"{item}.srs.json",
                base_dir / f"{item}.json",
            ]
        )

    for candidate in candidate_paths:
        if candidate.exists():
            return candidate.resolve()

    raise ValueError(f"Error: geosite json not found for '{item}' under '{base_dir}'.")


def convert_regex_to_exact_domain(regex_value: str) -> str | None:
    """Convert a simple anchored regex to an exact domain when possible."""

    match = EXACT_DOMAIN_REGEX_PATTERN.match(regex_value)
    if not match:
        return None
    return normalize_domain(match.group(1).replace(r"\.", "."))


def domain_matches_any_suffix(domain: str, suffixes: set[str]) -> bool:
    """Return whether a domain is covered by any suffix in the provided set."""

    current = domain
    while True:
        if current in suffixes:
            return True
        if "." not in current:
            return False
        current = current.partition(".")[2]


def matches_any_regex(domain: str, regexes: Iterable[re.Pattern[str]]) -> bool:
    """Return whether a domain matches any compiled exclusion regex."""

    return any(regex.search(domain) for regex in regexes)


def should_exclude_domain(domain: str, exclusions: ExclusionState) -> bool:
    """Return whether a domain should be removed by exclusion rules."""

    if domain in exclusions.exact_domains:
        return True
    if domain_matches_any_suffix(domain, exclusions.suffix_domains):
        return True
    return matches_any_regex(domain, exclusions.compiled_regexes)


def add_entry(entries: EntryState, entry_kind: str, entry_value: str) -> None:
    """Merge one geosite entry into the in-memory result sets."""

    if not entry_value or entry_value == "null":
        return

    if entry_kind == "domain":
        normalized = normalize_domain(entry_value)
        if normalized:
            entries.exact_domains.add(normalized)
        return

    if entry_kind == "suffix":
        normalized = normalize_domain(entry_value)
        if normalized:
            entries.suffix_domains.add(normalized)
        return

    if entry_kind == "regex":
        converted_domain = convert_regex_to_exact_domain(entry_value)
        if converted_domain:
            entries.exact_domains.add(converted_domain)
        else:
            entries.unsupported_regex.add(entry_value)
        return

    if entry_kind == "keyword":
        entries.unsupported_keyword.add(entry_value)


def emit_rule_values(entry_kind: str, entry_value: object) -> Iterator[tuple[str, str]]:
    """Emit legacy jq-style key/value pairs from a geosite rule field."""

    if entry_value is None:
        return

    if isinstance(entry_value, list):
        for item in entry_value:
            yield entry_kind, str(item)
        return

    yield entry_kind, str(entry_value)


def iter_rule_entries(source_json: Path) -> Iterator[tuple[str, str]]:
    """Yield flattened geosite rule entries from a JSON source file."""

    with source_json.open("r", encoding="utf-8") as handle:
        payload = json.load(handle)

    for rule in payload.get("rules", []):
        if not isinstance(rule, dict):
            continue
        yield from emit_rule_values("domain", rule.get("domain"))
        yield from emit_rule_values("suffix", rule.get("domain_suffix"))
        yield from emit_rule_values("regex", rule.get("domain_regex"))
        yield from emit_rule_values("keyword", rule.get("domain_keyword"))


def load_source_entries(source_json: Path, entries: EntryState) -> int:
    """Load and merge entries from one geosite JSON file."""

    entry_count = 0
    for entry_kind, entry_value in iter_rule_entries(source_json):
        add_entry(entries, entry_kind, entry_value)
        entry_count += 1
    return entry_count


def deduplicate_domains(entries: EntryState) -> GeneratedDomains:
    """Drop redundant suffix and exact domains just like the legacy script."""

    kept_suffix_domains: set[str] = set()
    for suffix_domain in entries.suffix_domains:
        parent_suffix = suffix_domain
        suffix_redundant = False
        while "." in parent_suffix:
            parent_suffix = parent_suffix.partition(".")[2]
            if parent_suffix in entries.suffix_domains:
                suffix_redundant = True
                break
        if not suffix_redundant:
            kept_suffix_domains.add(suffix_domain)

    kept_exact_domains: set[str] = set()
    for exact_domain in entries.exact_domains:
        exact_redundant = exact_domain in kept_suffix_domains
        parent_domain = exact_domain
        while not exact_redundant and "." in parent_domain:
            parent_domain = parent_domain.partition(".")[2]
            if parent_domain in kept_suffix_domains:
                exact_redundant = True
        if not exact_redundant:
            kept_exact_domains.add(exact_domain)

    return GeneratedDomains(
        suffix_domains=kept_suffix_domains,
        exact_domains=kept_exact_domains,
        dedup_suffix_count=len(kept_suffix_domains),
        dedup_exact_count=len(kept_exact_domains),
    )


def build_exclusions(options: Options) -> ExclusionState:
    """Normalize and compile exclusion rules from command-line options."""

    exclusions = ExclusionState()

    for exclude_domain in options.exclude_domains:
        normalized = normalize_domain(exclude_domain)
        if normalized:
            exclusions.exact_domains.add(normalized)

    for exclude_suffix in options.exclude_domain_suffixes:
        normalized = normalize_domain(exclude_suffix)
        if normalized:
            exclusions.suffix_domains.add(normalized)

    for exclude_regex in options.exclude_domain_regexes:
        try:
            compiled_regex = re.compile(exclude_regex)
        except re.error:
            exclusions.invalid_regex.add(exclude_regex)
            continue
        exclusions.regex_patterns.append(exclude_regex)
        exclusions.compiled_regexes.append(compiled_regex)

    return exclusions


def apply_exclusions(domains: GeneratedDomains, exclusions: ExclusionState) -> None:
    """Remove deduplicated domains covered by the exclusion rules."""

    kept_suffix_domains: set[str] = set()
    for suffix_domain in domains.suffix_domains:
        if should_exclude_domain(suffix_domain, exclusions):
            domains.excluded_suffix_count += 1
        else:
            kept_suffix_domains.add(suffix_domain)
    domains.suffix_domains = kept_suffix_domains

    kept_exact_domains: set[str] = set()
    for exact_domain in domains.exact_domains:
        if should_exclude_domain(exact_domain, exclusions):
            domains.excluded_exact_count += 1
        else:
            kept_exact_domains.add(exact_domain)
    domains.exact_domains = kept_exact_domains

    for exclude_domain in exclusions.exact_domains:
        parent_domain = exclude_domain
        while "." in parent_domain:
            parent_domain = parent_domain.partition(".")[2]
            if parent_domain in domains.suffix_domains:
                exclusions.unapplied_exact_excludes.add(exclude_domain)
                break


def build_nftset_value(ipv4_sets: list[str], ipv6_sets: list[str]) -> str:
    """Build the SmartDNS nftset option value for the first IPv4/IPv6 targets."""

    nftset_parts: list[str] = []
    if ipv4_sets:
        nftset_parts.append(f"#4:{ipv4_sets[0]}")
    if ipv6_sets:
        nftset_parts.append(f"#6:{ipv6_sets[0]}")
    return ",".join(nftset_parts)


def build_render_targets(options: Options, generated_dir: Path) -> RenderTargets:
    """Resolve output file names and derived identifiers."""

    output_slug = sanitize_file_component(options.output_name)
    list_file = generated_dir / f"60-{output_slug}.list"
    conf_file = generated_dir / f"60-{output_slug}.conf"
    return RenderTargets(
        output_slug=output_slug,
        domain_set_name=sanitize_symbol(f"geosite_{output_slug}"),
        list_file=list_file,
        conf_file=conf_file,
        list_basename=list_file.name,
        nftset_value=build_nftset_value(options.nftset_ipv4, options.nftset_ipv6),
    )


def write_lines(path: Path, lines: Iterable[str]) -> None:
    """Write a text file using Unix newlines."""

    with path.open("w", encoding="utf-8", newline="\n") as handle:
        for line in lines:
            handle.write(f"{line}\n")


def iter_list_lines(context: GenerationContext) -> Iterator[str]:
    """Yield the contents of the generated SmartDNS domain list file."""

    yield f"# Generated by {current_script_name()}"
    if context.resolved_sources:
        for source_json in context.resolved_sources:
            yield f"# {source_json}"
    else:
        yield "# custom-input-only"

    if (
        context.options.custom_domains
        or context.options.custom_domain_suffixes
        or context.options.custom_domain_regexes
    ):
        yield (
            "# custom "
            f"domain={len(context.options.custom_domains)} "
            f"suffix={len(context.options.custom_domain_suffixes)} "
            f"regex={len(context.options.custom_domain_regexes)}"
        )

    if (
        context.exclusions.exact_domains
        or context.exclusions.suffix_domains
        or context.exclusions.regex_patterns
        or context.exclusions.invalid_regex
    ):
        yield (
            "# exclude "
            f"domain={len(context.exclusions.exact_domains)} "
            f"suffix={len(context.exclusions.suffix_domains)} "
            f"regex={len(context.exclusions.regex_patterns)} "
            f"invalid-regex={len(context.exclusions.invalid_regex)}"
        )

    yield from sorted(context.domains.suffix_domains)

    yield from (f"-.{exact_domain}" for exact_domain in sorted(context.domains.exact_domains))


def extend_note_lines(lines: list[str], header: str, values: Iterable[str]) -> None:
    """Append a heading and sorted indented note entries."""

    sorted_values = sorted(values)
    if not sorted_values:
        return
    lines.append(header)
    lines.extend(f"#     {value}" for value in sorted_values)


def build_domain_rule_line(context: GenerationContext) -> str:
    """Build the SmartDNS domain-rules line for the generated set."""

    rule_line = f"domain-rules /domain-set:{context.targets.domain_set_name}/"
    if context.options.speed_check_mode:
        rule_line += f" -speed-check-mode {context.options.speed_check_mode}"
    if context.options.dns_group:
        rule_line += f" -nameserver {context.options.dns_group}"
    if context.options.disable_ipv6:
        rule_line += " -address #6"
    if context.targets.nftset_value:
        rule_line += f" -nftset {context.targets.nftset_value}"
    return rule_line


def iter_config_lines(context: GenerationContext) -> Iterator[str]:
    """Yield the contents of the generated SmartDNS config file."""

    yield f"# Generated by {current_script_name()}"
    yield "# Sources:"
    if context.resolved_sources:
        yield from (f"#   {source_json}" for source_json in context.resolved_sources)
    else:
        yield "#   custom-input-only"

    if (
        context.options.custom_domains
        or context.options.custom_domain_suffixes
        or context.options.custom_domain_regexes
    ):
        yield (
            "# Custom inputs: "
            f"domain={len(context.options.custom_domains)}, "
            f"suffix={len(context.options.custom_domain_suffixes)}, "
            f"regex={len(context.options.custom_domain_regexes)}"
        )

    if (
        context.exclusions.exact_domains
        or context.exclusions.suffix_domains
        or context.exclusions.regex_patterns
        or context.exclusions.invalid_regex
    ):
        yield (
            "# Exclusions: "
            f"domain={len(context.exclusions.exact_domains)}, "
            f"suffix={len(context.exclusions.suffix_domains)}, "
            f"regex={len(context.exclusions.regex_patterns)}, "
            f"invalid-regex={len(context.exclusions.invalid_regex)}"
        )
        yield (
            "# Excluded merged entries: "
            f"suffix={context.domains.excluded_suffix_count}, "
            f"exact={context.domains.excluded_exact_count}"
        )

    supported_domain_count = (
        len(context.domains.suffix_domains) + len(context.domains.exact_domains)
    )
    suffix_count = len(context.domains.suffix_domains)
    exact_count = len(context.domains.exact_domains)
    yield (
        "# Supported domains: "
        f"{supported_domain_count} "
        f"(suffix={suffix_count}, exact={exact_count})"
    )
    yield ""

    if supported_domain_count > 0:
        yield (
            f"domain-set -name {context.targets.domain_set_name} "
            f"-file /etc/smartdns/generated.d/{context.targets.list_basename}"
        )
        if context.targets.nftset_value:
            yield "nftset-timeout yes"
        yield build_domain_rule_line(context)
    else:
        yield (
            "# No SmartDNS-compatible domain or domain_suffix entries were "
            "generated."
        )

    notes: list[str] = []
    if len(context.options.nftset_ipv4) > 1:
        notes.append(
            "#   Additional IPv4 nftsets were ignored by SmartDNS: "
            f"{' '.join(context.options.nftset_ipv4[1:])}"
        )
    if len(context.options.nftset_ipv6) > 1:
        notes.append(
            "#   Additional IPv6 nftsets were ignored by SmartDNS: "
            f"{' '.join(context.options.nftset_ipv6[1:])}"
        )

    extend_note_lines(
        notes,
        "#   Unsupported domain_regex entries:",
        context.entries.unsupported_regex,
    )
    extend_note_lines(
        notes,
        "#   Unsupported domain_keyword entries:",
        context.entries.unsupported_keyword,
    )
    extend_note_lines(
        notes,
        "#   Invalid exclude-domain-regex entries (extended regex syntax):",
        context.exclusions.invalid_regex,
    )
    extend_note_lines(
        notes,
        (
            "#   Exact exclusions still covered by a broader kept suffix and "
            "cannot be carved out exactly:"
        ),
        context.exclusions.unapplied_exact_excludes,
    )

    if notes:
        yield ""
        yield "# Notes:"
        yield from notes


def ensure_inputs_present(options: Options, default_generated_dir: Path) -> None:
    """Validate that at least one source of domains was requested."""

    if (
        options.sources
        or options.custom_domains
        or options.custom_domain_suffixes
        or options.custom_domain_regexes
    ):
        return

    raise CommandLineError(
        "Error: at least one --source, --domain, --domain-suffix or --domain-regex is required.\n"
        f"{format_usage(default_generated_dir)}"
    )


def build_generation_context(options: Options, default_generated_dir: Path) -> GenerationContext:
    """Load, merge, deduplicate, and filter all requested geosite entries."""

    geosite_dir = resolve_from_script_dir(options.geosite_dir)
    generated_dir = resolve_from_script_dir(options.generated_dir or str(default_generated_dir))
    generated_dir.mkdir(parents=True, exist_ok=True)

    entries = EntryState()
    exclusions = build_exclusions(options)
    resolved_sources: list[Path] = []

    progress(
        "start "
        f"name={options.output_name} "
        f"source={len(options.sources)} "
        f"custom-domain={len(options.custom_domains)} "
        f"custom-suffix={len(options.custom_domain_suffixes)} "
        f"custom-regex={len(options.custom_domain_regexes)} "
        f"exclude-domain={len(options.exclude_domains)} "
        f"exclude-suffix={len(options.exclude_domain_suffixes)} "
        f"exclude-regex={len(options.exclude_domain_regexes)}"
    )

    for custom_domain in options.custom_domains:
        add_entry(entries, "domain", custom_domain)
    for custom_suffix in options.custom_domain_suffixes:
        add_entry(entries, "suffix", custom_suffix)
    for custom_regex in options.custom_domain_regexes:
        add_entry(entries, "regex", custom_regex)

    if options.custom_domains or options.custom_domain_suffixes or options.custom_domain_regexes:
        progress("loaded custom inputs")

    if (
        exclusions.exact_domains
        or exclusions.suffix_domains
        or exclusions.regex_patterns
        or exclusions.invalid_regex
    ):
        progress(
            "loaded exclusions "
            f"exact={len(exclusions.exact_domains)} "
            f"suffix={len(exclusions.suffix_domains)} "
            f"regex={len(exclusions.regex_patterns)} "
            f"invalid-regex={len(exclusions.invalid_regex)}"
        )

    for source_index, source_item in enumerate(options.sources, start=1):
        progress(f"[{source_index}/{len(options.sources)}] loading {source_item}")
        source_json = resolve_geosite_json(source_item, geosite_dir)
        resolved_sources.append(source_json)
        source_entry_count = load_source_entries(source_json, entries)
        progress(
            f"[{source_index}/{len(options.sources)}] parsed {source_entry_count} "
            f"entries from {source_json.name}"
        )

    progress(
        "normalizing and removing redundant domains "
        f"(suffix={len(entries.suffix_domains)} exact={len(entries.exact_domains)})"
    )
    domains = deduplicate_domains(entries)

    if exclusions.exact_domains or exclusions.suffix_domains or exclusions.compiled_regexes:
        progress("applying exclusions to deduplicated result")
        apply_exclusions(domains, exclusions)
        progress(
            "applied exclusions removed "
            f"suffix={domains.excluded_suffix_count} exact={domains.excluded_exact_count}"
        )

    progress(
        "deduplicated result "
        f"suffix={domains.dedup_suffix_count} "
        f"exact={domains.dedup_exact_count}; "
        f"final suffix={len(domains.suffix_domains)} "
        f"exact={len(domains.exact_domains)} "
        f"unsupported-regex={len(entries.unsupported_regex)} "
        f"unsupported-keyword={len(entries.unsupported_keyword)}"
    )

    return GenerationContext(
        options=options,
        resolved_sources=tuple(resolved_sources),
        entries=entries,
        exclusions=exclusions,
        domains=domains,
        targets=build_render_targets(options, generated_dir),
    )


def write_outputs(context: GenerationContext) -> None:
    """Render the generated list and config files to disk."""

    if context.targets.list_file.exists():
        context.targets.list_file.unlink()

    supported_domain_count = (
        len(context.domains.suffix_domains) + len(context.domains.exact_domains)
    )
    if supported_domain_count > 0:
        progress(f"writing list file {context.targets.list_file.name}")
        write_lines(context.targets.list_file, iter_list_lines(context))

    progress(f"writing config file {context.targets.conf_file.name}")
    write_lines(context.targets.conf_file, iter_config_lines(context))

    progress(
        "done "
        f"supported={supported_domain_count} "
        f"list={context.targets.list_file.name} "
        f"conf={context.targets.conf_file.name}"
    )
    print(f"Generated: {context.targets.conf_file}", file=sys.stderr)
    if context.targets.list_file.exists():
        print(f"Generated: {context.targets.list_file}", file=sys.stderr)


def main(arguments: list[str] | None = None) -> int:
    """Run the SmartDNS geosite generator."""

    default_generated_dir = load_default_smartdns_etc_dir() / "generated.d"
    cli_arguments = list(sys.argv[1:] if arguments is None else arguments)

    try:
        options = parse_arguments(cli_arguments)
        ensure_inputs_present(options, default_generated_dir)
        context = build_generation_context(options, default_generated_dir)
        write_outputs(context)
        return 0
    except UsageRequested:
        print(format_usage(default_generated_dir))
        return 0
    except CommandLineError as error:
        print(error, file=sys.stderr)
        return 1
    except (json.JSONDecodeError, OSError, ValueError) as error:
        message = str(error)
        if not message.startswith("Error:"):
            message = f"Error: {message}"
        print(message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
