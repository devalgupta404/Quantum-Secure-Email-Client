# aes_server.py - AES-GCM encryption service
from flask import Flask, request, jsonify
import requests, subprocess, binascii, os

KM = os.getenv("KM_URL", "http://127.0.0.1:8080")
AES_BIN = os.getenv("AES_GCM_BIN", os.path.abspath("./aes_gcm_demo"))  # .exe on Windows

app = Flask(__name__)

def b2h(b): return binascii.hexlify(b).decode()

def get_iv_hex():
    # IV doesn't need an id; 12B recommended
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
        # If KM didn't send a header, synthesize one (temporary)
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
    pt = request.get_data()
    aad_hex = request.headers.get("X-AAD-HEX", "")

    key_hex, key_id = get_new_key_and_id(16)
    iv_hex = get_iv_hex()

    args = [AES_BIN, key_hex, iv_hex]
    if aad_hex: args += ["--aad", aad_hex]
    try:
        proc = subprocess.run(args, input=pt, capture_output=True, check=True)
    except subprocess.CalledProcessError as e:
        return jsonify({"error": "crypto_failed", "detail": e.stderr.decode()}), 500

    lines = proc.stdout.decode().strip().splitlines()
    def after(label):
        for i, s in enumerate(lines):
            if s.strip().startswith(label): return lines[i+1].strip()
        return ""

    ct_hex  = after("CIPHERTEXT_HEX:")
    tag_hex = after("TAG_HEX:")
    if not ct_hex or not tag_hex:
        return jsonify({"error": "parse_failed", "stdout": lines}), 500

    # IMPORTANT: return key_id so client can store/use it for decryption
    return jsonify({
        "key_id": key_id,
        "iv_hex": iv_hex,
        "ciphertext_hex": ct_hex,
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
    aad_hex = body.get("aad_hex", "")

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

@app.get("/health")
def health_check():
    """Health check endpoint for Docker/Kubernetes"""
    try:
        # Test that AES binary is accessible
        proc = subprocess.run([AES_BIN, "--help"], capture_output=True, timeout=2)
        aes_status = "healthy" if proc.returncode == 0 else "degraded"
    except:
        aes_status = "unavailable"

    try:
        # Test connection to key manager
        r = requests.get(f"{KM}/health", timeout=2)
        km_status = "healthy" if r.status_code == 200 else "degraded"
    except:
        km_status = "unavailable"

    overall_status = "healthy" if aes_status == "healthy" and km_status == "healthy" else "degraded"

    return jsonify({
        "status": overall_status,
        "service": "aes-server",
        "version": "1.0",
        "dependencies": {
            "aes_binary": aes_status,
            "key_manager": km_status
        }
    }), 200 if overall_status == "healthy" else 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT","8082")))
