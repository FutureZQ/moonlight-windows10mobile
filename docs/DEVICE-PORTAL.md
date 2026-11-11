# Windows Device Portal access (Windows 10 Mobile 15254)

Everything in `DEBUG-HISTORY.md` was collected through the phone's Device
Portal. This file records the exact procedure, including the parts that are
not obvious from the documentation.

## 1. Enable the portal on the phone

Settings -> Update & security -> For developers -> **Device Portal** (on) and
note the URL: `https://<phone-ip>` (port 443, no path). Pairing PINs are only
needed for the "Device Portal for Xbox"-style flows; for HTTP access the portal
hands out a CSRF token to any client that can reach it, so treat the portal as
a full-control interface and keep it on a trusted network.

## 2. Get the cookie (the only "authentication" step)

The portal authenticates API calls with a **CSRF token stored in a cookie**.
You do not need a password or the pairing PIN.

```bash
curl -k -i https://192.168.10.34/ | findstr /i "set-cookie"
# Set-Cookie: CSRF-Token=46tBZNcMN9WusdOkNWfQuD33cyWSS4oK
```

Or from a desktop browser: open `https://<phone-ip>`, press F12, then
**Application -> Storage -> Cookies -> https://<phone-ip>** and copy the value
of `CSRF-Token`.

Notes:

- The value is 32 characters (`[A-Za-z0-9]`), no padding.
- The portal **rotates the token on most responses**: read `Set-Cookie` on
  every reply and use the new value from then on. A stale token gives
  `403 Forbidden` with an HTML body, not a JSON error.
- Older tooling also sends `WMID=<long digit string>` (a device identifier).
  It is not required on 15254; a fresh `CSRF-Token` alone is enough.
- Send the token **twice** for state-changing calls: in the `Cookie` header
  and in the `X-CSRF-Token` header.

## 3. Minimal Python client

```python
import ssl, re, json, urllib.request

IP = "192.168.10.34"
ctx = ssl._create_unverified_context()
ctx.check_hostname = False
ctx.set_ciphers("DEFAULT@SECLEVEL=0")          # portal uses old TLS ciphers
op = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ctx))
TOK = None

def call(path, data=None, method="GET", ctype=None, timeout=600):
    global TOK
    if TOK is None:                            # bootstrap: GET / sets the cookie
        with op.open(urllib.request.Request("https://%s/" % IP), timeout=20) as r:
            for sc in (r.headers.get_all("Set-Cookie") or []):
                m = re.search(r"CSRF-Token=([^;,\s]+)", sc)
                if m:
                    TOK = m.group(1)
    req = urllib.request.Request("https://%s%s" % (IP, path), data=data, method=method)
    req.add_header("Cookie", "CSRF-Token=%s" % TOK)
    req.add_header("X-CSRF-Token", TOK)        # required for POST/DELETE
    if ctype:
        req.add_header("Content-Type", ctype)
    try:
        with op.open(req, timeout=timeout) as resp:
            for sc in (resp.headers.get_all("Set-Cookie") or []):
                m = re.search(r"CSRF-Token=([^;,\s]+)", sc)
                if m:
                    TOK = m.group(1)           # rotate
            return resp.status, resp.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()

st, body = call("/api/os/info")
info = json.loads(body.decode("utf-8-sig"))    # responses start with a UTF-8 BOM
print(info["ComputerName"], info["OsVersion"])
```

Two traps that cost real time:

- **Decode responses with `utf-8-sig`.** `/api/os/info` (and others) start with
  a UTF-8 BOM; `json.loads(body.decode("utf-8"))` fails with
  `Unexpected UTF-8 BOM`.
- **Refresh the token from every response**, including error responses
  (`HTTPError.headers`).

## 4. Endpoints used for diagnostics

| Endpoint | Purpose |
|---|---|
| `GET /api/os/info` | device name, OS version, reachability probe |
| `GET /api/appx/packagemanager/packages` | installed packages, full names, install volume |
| `DELETE /api/appx/packagemanager/package?package=<full name>` | uninstall |
| `POST /api/app/packagemanager/package?package=<file name>` | install; body is `multipart/form-data` with one part named `package` |
| `GET /api/resourcemanager/processes` | process list; poll it to prove whether the app ever started |
| `GET /api/etw/providers` | provider list (GUIDs) |
| WebSocket `wss://<ip>/api/etw/session/realtime` | live ETW; the handshake **requires an `Origin: https://<ip>` header**, otherwise it times out |
| `GET /api/debug/dump/usermode/*` | full/mini dumps from `%LOCALAPPDATA%\CrashDumps` and `C:\Data\Users\Public\Dump` |

Dead ends on 15254:

- `/api/files/**` returns 400/500 for LocalState; use SSH instead.
- `/api/taskmanager/app` rejects base64 names; the `appid` parameter must be a
  **hex-encoded UTF-16LE** application id (`hex64`). It still fails for
  sideloaded packages, so the app cannot be launched programmatically.
- `/api/wer/reports` and `/api/authorize/pair` are not usable (404 / one-shot
  PIN expired).

## 5. Installing an appx without WinAppDeployCmd

```python
name = "moonlight-xbox-dx_1.18.3.0_ARM.appx"
blob = open(name, "rb").read()
boundary = "----dsh0000000000000001"
head = ('--%s\r\nContent-Disposition: form-data; name="package"; filename="%s"\r\n'
        'Content-Type: application/octet-stream\r\n\r\n' % (boundary, name)).encode()
body = head + blob + ("\r\n--%s--\r\n" % boundary).encode()
print(call("/api/app/packagemanager/package?package=%s" % name,
           data=body, method="POST",
           ctype="multipart/form-data; boundary=" + boundary))
# 202 {"Reason" : "Deploy request accepted and being processed"}
```

The request returns immediately; the install itself takes one to two minutes
and **replaces `LocalState`**. Copy `LocalState` somewhere on the phone
(`C:\Data\Users\Public\...`) before uninstalling and restore it afterwards.
