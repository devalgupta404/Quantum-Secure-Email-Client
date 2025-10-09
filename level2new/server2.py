# server.py
from flask import Flask, request, jsonify
import base64, json, binascii
import requests, subprocess, binascii, os

KM = os.getenv("KM_URL", "http://127.0.0.1:8080")
AES_BIN = os.getenv("AES_GCM_BIN", os.path.abspath("./aes_gcm_demo"))  # .exe on Windows

app = Flask(__name__)

def b2h(b): return binascii.hexlify(b).decode()

def json_to_hex(obj) -> str:
    # stable JSON (no spaces) -> UTF-8 -> hex
    s = json.dumps(obj, separators=(",", ":")) if not isinstance(obj, str) else obj
    return binascii.hexlify(s.encode("utf-8")).decode()

def get_pt_and_aad_hex(req):
    ct = (req.content_type or "").lower()
    aad_hex = ""
    pt = b""

    if ct.startswith("multipart/form-data"):
        f = req.files.get("file")
        if not f: return None, None, "missing multipart field 'file'"
        pt = f.read()
        aad_raw = req.form.get("aad")  # JSON string (optional)
        if aad_raw:
            try:
                # allow either raw JSON string or already-hex
                if aad_raw.strip().startswith("{"):
                    aad_hex = json_to_hex(json.loads(aad_raw))
                else:
                    aad_hex = aad_raw  # treat as hex if client insisted
            except Exception:
                return None, None, "bad 'aad' JSON"
    elif ct.startswith("application/json"):
        j = req.get_json(force=True, silent=True) or {}
        if "file_b64" in j:
            pt = base64.b64decode(j["file_b64"])
        elif "plaintext" in j:
            pt = (j["plaintext"] or "").encode("utf-8")
        else:
            return None, None, "missing file_b64/plaintext"
        if "aad" in j:
            aad_hex = json_to_hex(j["aad"])
        elif "aad_hex" in j:
            aad_hex = j["aad_hex"]
    else:  # application/octet-stream (raw bytes) + header X-AAD-HEX (optional)
        pt = req.get_data()
        aad_hex = req.headers.get("X-AAD-HEX", "")

    return pt, aad_hex, None











def get_iv_hex():
    # IV doesn’t need an id; 12B recommended
    r = requests.get(f"{KM}/otp/keys", params={"size": 12}, timeout=5)
    r.raise_for_status()
    # accept raw or json
    try:
        j = r.json()
        if "iv_hex" in j: return j["iv_hex"]
        if "key_hex" in j: return j["key_hex"]  # some KMs reuse same route
    except Exception:
        pass
    return b2h(r.content)

def get_new_key_and_id(bytes_needed=16):
    """
    Fetch a fresh key and its key_id from KM.
    Supported KM responses:
      - RAW body (key bytes) + header X-Key-Id
      - JSON: {"key_hex":"..","key_id":".."}  OR {"key":"<base64>","key_id":".."}
    """
    r = requests.get(f"{KM}/otp/keys", params={"size": bytes_needed}, timeout=5)
    r.raise_for_status()

    # Prefer header
    key_id = r.headers.get("X-Key-Id")

    # Try JSON
    key_hex = None
    if "application/json" in r.headers.get("Content-Type", ""):
        j = r.json()
        key_id = j.get("key_id") or key_id
        key_hex = j.get("key_hex")
        if not key_hex and "key" in j:  # base64?
            key_hex = b2h(binascii.a2b_base64(j["key"]))
    # Fallback raw
    if not key_hex:
        key_hex = b2h(r.content)

    if not key_id:
        # If KM didn’t send a header, try common fallback routes to mint an id:
        #   GET /otp/last_id or include a simple deterministic id (NOT ideal).
        # Best: update KM to send X-Key-Id. For now, synthesize one (temporary).
        key_id = "K-unknown-" + os.urandom(4).hex()

    return key_hex, key_id

def get_key_hex_by_id(key_id):
    """
    Resolve key bytes by key_id from KM. Tries common patterns:
      - GET /otp/keys/<key_id>
      - GET /otp/keys?id=<key_id>
      - GET /otp/key?id=<key_id>
    Accepts raw or JSON {key_hex}/base64.
    """
    paths = [
        f"{KM}/otp/keys/{key_id}",
        f"{KM}/otp/keys?id={key_id}",
        f"{KM}/otp/key?id={key_id}",
    ]
    for url in paths:
        try:
            r = requests.get(url, timeout=5)
            if r.status_code == 404:
                continue
            r.raise_for_status()
            if "application/json" in r.headers.get("Content-Type", ""):
                j = r.json()
                if "key_hex" in j: return j["key_hex"]
                if "key" in j:     return b2h(binascii.a2b_base64(j["key"]))
            return b2h(r.content)
        except Exception:
            continue
    raise RuntimeError("Key not found in KM for key_id=" + key_id)

@app.post("/api/gcm/encrypt")
def encrypt_gcm():
    pt, aad_hex, err = get_pt_and_aad_hex(request)  # <- unified input (multipart/json/raw)
    if err:
        return jsonify({"error": "bad_request", "detail": err}), 400

    key_hex, key_id = get_new_key_and_id(16)
    iv_hex = get_iv_hex()

    args = [AES_BIN, key_hex, iv_hex]
    if aad_hex:
        args += ["--aad", aad_hex]
    try:
        proc = subprocess.run(args, input=pt, capture_output=True, check=True)
    except subprocess.CalledProcessError as e:
        return jsonify({"error": "crypto_failed", "detail": e.stderr.decode()}), 500

    lines = proc.stdout.decode().strip().splitlines()
    def after(label):
        for i, s in enumerate(lines):
            if s.strip().startswith(label):
                return lines[i+1].strip() if i+1 < len(lines) else ""
        return ""

    ct_hex  = after("CIPHERTEXT_HEX:")
    tag_hex = after("TAG_HEX:")

    # allow empty ciphertext (encrypting empty file) but tag must exist
    if tag_hex == "":
        return jsonify({"error": "parse_failed", "stdout": lines}), 500

    return jsonify({
        "key_id": key_id,
        "iv_hex": iv_hex,
        "ciphertext_hex": ct_hex if ct_hex is not None else "",
        "tag_hex": tag_hex,
        "aad_hex": aad_hex
    })


@app.post("/api/gcm/decrypt")
def decrypt_gcm():
    body = request.get_json(force=True)
    key_id = body["key_id"]                 # <-- provided by client (from encrypt response)
    iv_hex = body["iv_hex"]
    ct_hex = body["ciphertext_hex"]
    tag_hex = body["tag_hex"]
    aad_hex = body.get("aad_hex") or (json_to_hex(body["aad"]) if "aad" in body else "")


    # Fetch the SAME key via key_id
    try:
        key_hex = get_key_hex_by_id(key_id)
    except Exception as e:
        return jsonify({"error": "key_lookup_failed", "detail": str(e)}), 404

    args = [AES_BIN, key_hex, iv_hex, "--dec", ct_hex, tag_hex]
    if aad_hex: args += ["--aad", aad_hex]

    proc = subprocess.run(args, capture_output=True)
    if proc.returncode != 0:
        return jsonify({"error": "auth_failed"}), 400

    # plaintext bytes out
    return proc.stdout, 200, {"Content-Type": "application/octet-stream"}


if __name__ == "__main__":
    import os
    app.run(host="0.0.0.0", port=int(os.getenv("PORT","8082")))