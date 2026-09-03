"""Addon mitmproxy para capturar trafico YouTube Music (Safari o la app Vibes).

Uso:
    python -m mitmdump -p 8080 -s Scripts\\ytm_capture.py

Genera en el directorio actual:
    ytm_flows.log   -> resumen legible con SECRETOS REDACTADOS (seguro para compartir)
    ytm_flows.mitm  -> flujos completos (CONTIENE COOKIES/TOKENS: no compartir)

Que probar en el iPhone (Safari, https://music.youtube.com):
    1. Login con Google
    2. Abrir "Liked Music" (Me gusta)
    3. Abrir una playlist propia
    4. Reproducir una cancion >1MB y dejarla sonar 1 min
"""
import json
import re

from mitmproxy import ctx

LOG = open("ytm_flows.log", "a", encoding="utf-8")

SENSITIVE = {"cookie", "authorization", "x-goog-visitor-id", "set-cookie"}


def redact(headers):
    out = {}
    for k, v in headers.items():
        kl = k.lower()
        if kl in SENSITIVE:
            if kl == "cookie":
                names = sorted({p.split("=")[0].strip() for p in v.split(";") if "=" in p})
                out[k] = f"[REDACTED {len(v)} chars, cookies={names}]"
            elif kl == "authorization":
                kind = v.split(" ")[0] if " " in v else "?"
                out[k] = f"[REDACTED {kind} len={len(v)}]"
            else:
                out[k] = f"[REDACTED len={len(v)}]"
        else:
            out[k] = v
    return out


def log(*parts):
    line = " ".join(str(p) for p in parts)
    LOG.write(line + "\n")
    LOG.flush()
    ctx.log.info(line)


def summarize_body(data: bytes, limit=1500):
    try:
        txt = data.decode("utf-8", errors="ignore")
    except Exception:
        return f"<{len(data)} bytes binarios>"
    # Redactar tokens/cookies si aparecen en el body
    txt = re.sub(r'"(access_token|refresh_token|id_token)"\s*:\s*"[^"]+"', r'"\1":"[REDACTED]"', txt)
    return txt[:limit]


def response(flow):
    req = flow.request
    host = req.host or ""
    path = req.path or ""
    resp = flow.response
    if resp is None:
        return

    # --- InnerTube API ---
    if "youtubei/v1/" in path and ("youtube.com" in host or "googleapis" in host):
        m = re.search(r"youtubei/v1/(\w+)", path)
        endpoint = m.group(1) if m else path
        try:
            body = json.loads(req.content or b"{}")
        except Exception:
            body = {}
        client = ((body.get("context") or {}).get("client") or {})
        logged = "?"
        try:
            rj = json.loads(resp.content or b"{}")
            for svc in ((rj.get("responseContext") or {}).get("serviceTrackingParams") or []):
                for prm in svc.get("params", []):
                    if prm.get("key") == "logged_in":
                        logged = prm.get("value")
            keys = list(rj.keys())
        except Exception:
            keys = ["<no-json>"]
        log(f"[API] {endpoint} client={client.get('clientName')}/{client.get('clientVersion')} "
            f"browseId={body.get('browseId')} videoId={body.get('videoId')} "
            f"-> {resp.status_code} logged_in={logged} respKeys={keys}")
        log(f"      reqHeaders={redact(req.headers)}")
        if resp.status_code >= 400:
            log(f"      errBody={summarize_body(resp.content or b'')}")
        return

    # --- googlevideo media ---
    if "googlevideo.com" in host and "videoplayback" in path:
        q = dict(req.query or [])
        for secret in ("sig", "lsig", "bui", "spc", "ip", "id", "ei"):
            if secret in q:
                q[secret] = q[secret][:6] + "..." if isinstance(q[secret], str) else q[secret]
        log(f"[MEDIA] rangeHdr={req.headers.get('Range')} rangeQ={q.get('range')} rn={q.get('rn')} "
            f"c={q.get('c')} itag={q.get('itag')} clen={q.get('clen')} n={'n' in q} -> {resp.status_code} "
            f"bytes={len(resp.content or b'')} cr={resp.headers.get('Content-Range')}")
        log(f"      UA={req.headers.get('User-Agent', '')[:80]} "
            f"cookie={'Cookie' in req.headers} referer={req.headers.get('Referer')}")
        return

    # --- login / oauth ---
    if "accounts.google.com" in host or "oauth2.googleapis.com" in host:
        log(f"[AUTH] {req.method} {host}{path.split('?')[0]} -> "
            f"{resp.status_code if resp else '?'}")
        return
