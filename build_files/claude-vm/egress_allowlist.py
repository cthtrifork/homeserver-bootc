#!/usr/bin/python3
"""Validate the egress allowlist and derive the sandbox, Envoy and dnsmasq configuration from it.

usage: egress_allowlist.py ALLOWLIST MANAGED_SETTINGS_JSON OUTDIR
"""

import argparse
import json
import re
import sys
from pathlib import Path

RESOLVER = "127.0.0.53"  # systemd-resolved stub

LABEL = r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?"
DOMAIN_RE = re.compile(rf"^{LABEL}(?:\.{LABEL})+$")
NUMERIC_RE = re.compile(r"^[0-9.]+$")
MAX_NAME = 253


def parse(text):
    entries = []
    for number, line in enumerate(text.splitlines(), start=1):
        entry = line.split("#", 1)[0].strip()
        if entry:
            entries.append((number, entry))
    return entries


def validate(entries):
    if not entries:
        return ["empty allowlist"]
    problems = []
    first_seen = {}
    for number, domain in entries:
        if len(domain) > MAX_NAME or not DOMAIN_RE.match(domain) or NUMERIC_RE.match(domain):
            problems.append(f"line {number}: invalid entry '{domain}'")
        elif domain in first_seen:
            problems.append(f"line {number}: duplicate of line {first_seen[domain]} ('{domain}')")
        else:
            first_seen[domain] = number
    for domain, number in first_seen.items():
        labels = domain.split(".")
        for i in range(1, len(labels) - 1):
            parent = ".".join(labels[i:])
            if parent in first_seen:
                problems.append(f"line {number}: '{domain}' is already covered by '{parent}'")
                break
    return problems


# One gateway listener pair per agent user, chosen by egress.nft from the UID of the process that connects. The ports are
# also in egress.nft; the user names are also in refresh-github-token's callers (claude-vm-github-token@<user>).
USERS = [("claude", 8443, 8008), ("claude-rc-personal", 8444, 8009)]

# Hosts whose TLS the gateway terminates, to add the calling user's GitHub token. Everything else is passed through by SNI.
# A group's `secret` file is written by refresh-github-token; `prefix` is put in front of its content. Keep the names in
# step with that script and with egress-ca (which makes one certificate per group).
INTERCEPTS = [
    {"name": "api", "hosts": ["api.github.com", "uploads.github.com"], "prefix": "Bearer "},
    {"name": "git", "hosts": ["github.com", "gist.github.com"], "prefix": "Basic "},
]
SECRET_DIR = "/run/claude-vm/envoy"
CA_DIR = "/var/lib/claude-vm/ca"
SYSTEM_CA_BUNDLE = "/etc/pki/tls/certs/ca-bundle.crt"
ENVOY = "type.googleapis.com/envoy.extensions"
DNS_CACHE = {"name": "egress_dns", "dns_lookup_family": "V4_ONLY"}

def covered(host, domains):
    return any(host == d or host.endswith("." + d) for d in domains)


def log(prefix, extra_filter=None):
    entry = {
        "name": "envoy.access_loggers.stderr",
        "typed_config": {
            "@type": f"{ENVOY}.access_loggers.stream.v3.StderrAccessLog",
            "log_format": {"text_format_source": {"inline_string": prefix + " client=%DOWNSTREAM_REMOTE_ADDRESS_WITHOUT_PORT%\n"}},
        },
    }
    if extra_filter:
        entry["filter"] = extra_filter
    return [entry]


def hcm(name, route_config, http_filters, **extra):
    return {
        "name": "envoy.filters.network.http_connection_manager",
        "typed_config": {
            "@type": f"{ENVOY}.filters.network.http_connection_manager.v3.HttpConnectionManager",
            "stat_prefix": name,
            "strip_any_host_port": True,
            "route_config": route_config,
            "http_filters": http_filters + [
                {"name": "envoy.filters.http.router", "typed_config": {"@type": f"{ENVOY}.filters.http.router.v3.Router"}}
            ],
            **extra,
        },
    }


def dfp_filter():
    return {
        "name": "envoy.filters.http.dynamic_forward_proxy",
        "typed_config": {"@type": f"{ENVOY}.filters.http.dynamic_forward_proxy.v3.FilterConfig", "dns_cache_config": DNS_CACHE},
    }


def drop_client_authorization():
    # Whatever the client sends is not trusted (the gh wrapper sends a placeholder): without this, a gateway that has no
    # token yet would pass the placeholder on and GitHub would answer 401 even to anonymous reads of public repositories.
    return {
        "name": "envoy.filters.http.header_mutation",
        "typed_config": {
            "@type": f"{ENVOY}.filters.http.header_mutation.v3.HeaderMutation",
            "mutations": {"request_mutations": [{"remove": "authorization"}]},
        },
    }


def deny_vhost():
    return {
        "name": "blocked",
        "domains": ["*"],
        "routes": [{"match": {"prefix": "/"}, "direct_response": {"status": 403, "body": {"inline_string": "blocked by the claude-vm egress allowlist\n"}}}],
    }


def https_listener(user, port, domains):
    chains = []
    exact = set()
    for group in INTERCEPTS:
        exact.update(group["hosts"])
        vhosts = [
            {
                "name": host.replace(".", "_"),
                "domains": [host],
                "routes": [
                    {
                        "match": {"prefix": "/"},
                        "route": {"cluster": "dfp_tls"},
                        # the filter takes the port from :authority, and clients send none for 443
                        "typed_per_filter_config": {
                            "envoy.filters.http.dynamic_forward_proxy": {
                                "@type": f"{ENVOY}.filters.http.dynamic_forward_proxy.v3.PerRouteConfig",
                                "host_rewrite_literal": f"{host}:443",
                            }
                        },
                    }
                ],
            }
            for host in group["hosts"]
        ]
        injector = {
            "name": "envoy.filters.http.credential_injector",
            "typed_config": {
                "@type": f"{ENVOY}.filters.http.credential_injector.v3.CredentialInjector",
                # without a token (App not set up yet) the request goes out unauthenticated instead of failing
                "allow_request_without_credential": True,
                "overwrite": True,
                "credential": {
                    "name": "envoy.http.injected_credentials.generic",
                    "typed_config": {
                        "@type": f"{ENVOY}.http.injected_credentials.generic.v3.Generic",
                        "header": "Authorization",
                        "header_value_prefix": group["prefix"],
                        "credential": {
                            "name": "credential",
                            "sds_config": {
                                "path_config_source": {
                                    "path": f"{SECRET_DIR}/{user}-{group['name']}.json",
                                    "watched_directory": {"path": SECRET_DIR},
                                }
                            },
                        },
                    },
                },
            },
        }
        chains.append(
            {
                "filter_chain_match": {"server_names": list(group["hosts"])},
                "transport_socket": {
                    "name": "envoy.transport_sockets.tls",
                    "typed_config": {
                        "@type": f"{ENVOY}.transport_sockets.tls.v3.DownstreamTlsContext",
                        "common_tls_context": {
                            "alpn_protocols": ["http/1.1"],
                            "tls_certificates": [
                                {
                                    "certificate_chain": {"filename": f"{CA_DIR}/{group['name']}.pem"},
                                    "private_key": {"filename": f"{CA_DIR}/{group['name']}.key"},
                                }
                            ],
                        },
                    },
                },
                "filters": [
                    hcm(
                        f"{user}_{group['name']}",
                        {"name": "intercept", "virtual_hosts": vhosts + [deny_vhost()]},
                        [drop_client_authorization(), injector, dfp_filter()],
                    )
                ],
            }
        )
    names = [n for d in domains for n in (d, f"*.{d}") if n not in exact]
    chains.append(
        {
            "filter_chain_match": {"server_names": names},
            "filters": [
                {
                    "name": "envoy.filters.network.sni_dynamic_forward_proxy",
                    "typed_config": {
                        "@type": f"{ENVOY}.filters.network.sni_dynamic_forward_proxy.v3.FilterConfig",
                        "dns_cache_config": DNS_CACHE,
                        "port_value": 443,
                    },
                },
                {
                    "name": "envoy.filters.network.tcp_proxy",
                    "typed_config": {"@type": f"{ENVOY}.filters.network.tcp_proxy.v3.TcpProxy", "stat_prefix": f"{user}_sni", "cluster": "dfp_tcp"},
                },
            ],
        }
    )
    return {
        "name": f"https_{user}",
        "address": {"socket_address": {"address": "127.0.0.1", "port_value": port}},
        "listener_filters": [
            {"name": "envoy.filters.listener.tls_inspector", "typed_config": {"@type": f"{ENVOY}.filters.listener.tls_inspector.v3.TlsInspector"}}
        ],
        "filter_chains": chains,
        # not on the list (or no SNI at all, e.g. an IP address): refused upstream, so the client sees a reset
        "default_filter_chain": {
            "filters": [
                {
                    "name": "envoy.filters.network.tcp_proxy",
                    "typed_config": {
                        "@type": f"{ENVOY}.filters.network.tcp_proxy.v3.TcpProxy",
                        "stat_prefix": f"{user}_blocked",
                        "cluster": "blackhole",
                        "access_log": log("egress_blocked: https %REQUESTED_SERVER_NAME%"),
                    },
                }
            ]
        },
    }


def http_listener(user, port, domains):
    allowed = {
        "name": "allowed",
        "domains": [n for d in domains for n in (d, f"*.{d}")],
        "routes": [{"match": {"prefix": "/"}, "route": {"cluster": "dfp_tcp"}}],
    }
    return {
        "name": f"http_{user}",
        "address": {"socket_address": {"address": "127.0.0.1", "port_value": port}},
        "filter_chains": [
            {
                "filters": [
                    hcm(
                        f"{user}_http",
                        {"name": "plain", "virtual_hosts": [allowed, deny_vhost()]},
                        [dfp_filter()],
                        # the blocked line is for requests the allowlist refused (a 403 the upstream sent is logged too)
                        access_log=log("egress_blocked: http %REQ(:AUTHORITY)%", {"status_code_filter": {"comparison": {"op": "EQ", "value": {"default_value": 403, "runtime_key": "egress.http_403"}}}}),
                    )
                ]
            }
        ],
    }


def envoy_config(domains):
    for group in INTERCEPTS:
        for host in group["hosts"]:
            if not covered(host, domains):
                raise SystemExit(f"intercepted host '{host}' is not on the allowlist")
    dfp = {"@type": f"{ENVOY}.clusters.dynamic_forward_proxy.v3.ClusterConfig", "dns_cache_config": DNS_CACHE}
    cluster = {"lb_policy": "CLUSTER_PROVIDED", "cluster_type": {"name": "envoy.clusters.dynamic_forward_proxy", "typed_config": dfp}}
    return {
        # SDS (the injected credentials) refuses to load without a node identity
        "node": {"id": "claude-vm-egress", "cluster": "claude-vm-egress"},
        "static_resources": {
            "listeners": [l for user, https, http in USERS for l in (https_listener(user, https, domains), http_listener(user, http, domains))],
            "clusters": [
                {"name": "dfp_tcp", **cluster},
                {
                    "name": "dfp_tls",
                    **cluster,
                    # Envoy sets the SNI and checks the certificate against the resolved host name by itself
                    "transport_socket": {
                        "name": "envoy.transport_sockets.tls",
                        "typed_config": {
                            "@type": f"{ENVOY}.transport_sockets.tls.v3.UpstreamTlsContext",
                            "common_tls_context": {"validation_context": {"trusted_ca": {"filename": SYSTEM_CA_BUNDLE}}},
                        },
                    },
                },
                {
                    "name": "blackhole",
                    "type": "STATIC",
                    "connect_timeout": "1s",
                    "load_assignment": {
                        "cluster_name": "blackhole",
                        "endpoints": [{"lb_endpoints": [{"endpoint": {"address": {"socket_address": {"address": "127.0.0.1", "port_value": 9}}}}]}],
                    },
                },
            ],
        }
    }


def build(allowlist, settings_path, outdir):
    entries = parse(allowlist.read_text())
    problems = validate(entries)
    if problems:
        raise SystemExit("\n".join(f"{allowlist}: {p}" for p in problems))
    domains = sorted(domain for _, domain in entries)

    settings = json.loads(settings_path.read_text())
    settings.setdefault("sandbox", {}).setdefault("network", {})["allowedDomains"] = [
        name for d in domains for name in (d, f"*.{d}")
    ]
    settings_path.write_text(json.dumps(settings, indent=2) + "\n")

    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "allowlist.txt").write_text("".join(f"{d}\n" for d in domains))
    (outdir / "envoy.json").write_text(json.dumps(envoy_config(domains), indent=2) + "\n")
    (outdir / "intercepts.json").write_text(json.dumps(INTERCEPTS, indent=2) + "\n")
    (outdir / "dnsmasq-servers").write_text("".join(f"server=/{d}/{RESOLVER}\n" for d in domains))
    return domains


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("allowlist", type=Path)
    parser.add_argument("managed_settings", type=Path)
    parser.add_argument("outdir", type=Path)
    args = parser.parse_args()
    domains = build(args.allowlist, args.managed_settings, args.outdir)
    print(f"egress-allowlist: {len(domains)} domains")


if __name__ == "__main__":
    main()
