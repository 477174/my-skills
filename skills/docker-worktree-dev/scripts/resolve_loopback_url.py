"""Reroute nip.io loopback URLs through the Docker host gateway.

Problem: nip.io resolves to its embedded IP. When that is a loopback address
(e.g. 127.0.0.1), inside a container it means the container itself — so a
container-to-container or container-to-host call through a nip.io URL connects
to the wrong place or fails. Rewrite such URLs to host.docker.internal and
preserve the original Host header so virtual-host routing still works.

Requires `extra_hosts: ["host.docker.internal:host-gateway"]` on the service
(Linux). Import resolve_loopback_url() in your HTTP client, or run this file
directly to test a URL:  python resolve_loopback_url.py http://x.127.0.0.1.nip.io
"""

from __future__ import annotations

import ipaddress
import socket
from urllib.parse import urlparse, urlunparse


def resolve_loopback_url(url: str) -> tuple[str, str | None]:
    """Return (possibly_rewritten_url, original_netloc_or_none).

    When original_netloc is not None, send it as the Host header so the
    upstream still routes by the intended virtual host.
    """
    parsed = urlparse(url)
    hostname = parsed.hostname
    if not hostname:
        return url, None
    try:
        resolved_ip = socket.gethostbyname(hostname)
    except socket.gaierror:
        return url, None
    if not ipaddress.ip_address(resolved_ip).is_loopback:
        return url, None
    rewritten = parsed._replace(
        netloc=parsed.netloc.replace(hostname, "host.docker.internal")
    )
    return urlunparse(rewritten), parsed.netloc


if __name__ == "__main__":
    import sys

    if len(sys.argv) != 2:
        print("usage: resolve_loopback_url.py <url>", file=sys.stderr)
        raise SystemExit(2)
    new_url, host_header = resolve_loopback_url(sys.argv[1])
    print(f"url:  {new_url}")
    print(f"host: {host_header or '(unchanged)'}")
