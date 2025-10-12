# otp_server.py - Pure OTP encryption service
from flask import Flask, request, jsonify
import requests, binascii, os, base64

KM = os.getenv("KM_URL", "http://127.0.0.1:2020")

app = Flask(__name__)

def b2h(b): return binascii.hexlify(b).decode()

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

@app.post("/api/otp/encrypt")
def encrypt_otp():
    """OTP encryption endpoint"""
    try:
        body = request.get_json()
        if not body or "text" not in body:
            return jsonify({"error": "Missing text field"}), 400

        plaintext = body["text"]

        # Get a new key for OTP encryption
        key_hex, key_id = get_new_key_and_id(len(plaintext.encode('utf-8')))
        key_bytes = binascii.unhexlify(key_hex)
        plaintext_bytes = plaintext.encode('utf-8')

        # XOR encryption (OTP)
        ciphertext_bytes = bytearray()
        for i, byte in enumerate(plaintext_bytes):
            ciphertext_bytes.append(byte ^ key_bytes[i % len(key_bytes)])

        # Convert to base64url
        ciphertext_b64url = base64.urlsafe_b64encode(ciphertext_bytes).decode('ascii').rstrip('=')

        return jsonify({
            "key_id": key_id,
            "ciphertext_b64url": ciphertext_b64url
        })
    except Exception as e:
        return jsonify({"error": "encryption_failed", "detail": str(e)}), 500

@app.post("/api/otp/decrypt")
def decrypt_otp():
    """OTP decryption endpoint"""
    try:
        body = request.get_json()
        if not body or "key_id" not in body or "ciphertext_b64url" not in body:
            return jsonify({"error": "Missing required fields"}), 400

        key_id = body["key_id"]
        ciphertext_b64url = body["ciphertext_b64url"]

        # Convert from base64url
        # Add padding if needed
        missing_padding = len(ciphertext_b64url) % 4
        if missing_padding:
            ciphertext_b64url += '=' * (4 - missing_padding)
        ciphertext_bytes = base64.urlsafe_b64decode(ciphertext_b64url)

        # Get the key
        key_hex = get_key_hex_by_id(key_id)
        key_bytes = binascii.unhexlify(key_hex)

        # XOR decryption (OTP)
        plaintext_bytes = bytearray()
        for i, byte in enumerate(ciphertext_bytes):
            plaintext_bytes.append(byte ^ key_bytes[i % len(key_bytes)])

        return jsonify({
            "text": plaintext_bytes.decode('utf-8')
        }), 200
    except Exception as e:
        return jsonify({"error": "decryption_failed", "detail": str(e)}), 500

@app.get("/health")
def health_check():
    """Health check endpoint for Docker/Kubernetes"""
    try:
        # Test connection to key manager
        r = requests.get(f"{KM}/health", timeout=2)
        km_status = "healthy" if r.status_code == 200 else "degraded"
    except:
        km_status = "unavailable"

    overall_status = "healthy" if km_status == "healthy" else "degraded"

    return jsonify({
        "status": overall_status,
        "service": "otp-server",
        "version": "1.0",
        "dependencies": {
            "key_manager": km_status
        }
    }), 200 if overall_status == "healthy" else 503

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT","2021")))
