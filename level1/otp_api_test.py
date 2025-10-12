# otp_api.py  — Encoder + Decoder HTTP API for OTP via your C encoder.exe
# Frontend calls this; it shells out to encoder.exe Level 1 (OTP via KM).
import os, base64, tempfile, subprocess, shutil
from flask import Flask, request, jsonify, abort

app = Flask(__name__)

# ---------- Config & discovery ----------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
env_exe = os.environ.get("ENCODER_EXE")  # optionally set this to the full path
CANDIDATES = [
    env_exe,
    os.path.join(SCRIPT_DIR, "level1", "encoder.exe"),  # ADD THIS LINE
    os.path.join(SCRIPT_DIR, "encoder.exe"),
    os.path.join(SCRIPT_DIR, "encoder"),
    os.path.abspath("./level1/encoder.exe"),  # ADD THIS LINE
    os.path.abspath("./encoder.exe"),
    os.path.abspath("./encoder"),
    shutil.which("encoder"),
    shutil.which("encoder.exe"),
]
CANDIDATES = [p for p in CANDIDATES if p]
ENCODER_EXE = next((p for p in CANDIDATES if p and os.path.exists(p)), None)

MAX_BYTES = int(os.environ.get("OTP_MAX_BYTES", "2000000"))  # 2 MB default

def b64url_encode(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).rstrip(b"=").decode("ascii")

def b64url_decode(s: str) -> bytes:
    pad = "=" * (-len(s) % 4)
    return base64.urlsafe_b64decode(s + pad)

def must_have_encoder():
    if not ENCODER_EXE or not os.path.exists(ENCODER_EXE):
        abort(500, f"encoder.exe not found (checked: {CANDIDATES})")

# ---------- Encrypt ----------
@app.post("/api/otp/encrypt")
def api_encrypt():
    """
    Request (one of):
      { "text": "hello world" }
      { "plaintext_b64url": "<...>" }

    Response:
      { "key_id": "<...>", "ciphertext_b64url": "<...>" }
    """
    must_have_encoder()
    body = request.get_json(silent=True) or {}

    if "text" in body:
        pt = body["text"].encode("utf-8")
    elif "plaintext_b64url" in body:
        try:
            pt = b64url_decode(body["plaintext_b64url"])
        except Exception:
            abort(400, "Invalid Base64URL in 'plaintext_b64url'")
    else:
        abort(400, "Provide 'text' or 'plaintext_b64url'")

    if not pt:
        abort(400, "Plaintext must be non-empty")
    if len(pt) > MAX_BYTES:
        abort(413, f"Plaintext too large (max {MAX_BYTES} bytes)")

    with tempfile.TemporaryDirectory() as td:
        plain_path  = os.path.join(td, "plain.txt")
        cipher_path = os.path.join(td, "cipher.bin")
        keyid_path  = os.path.join(td, "key_id.txt")

        with open(plain_path, "wb") as f:
            f.write(pt)

        # Let your encoder.exe handle KM & XOR:  encoder.exe 1 enc <plain> <cipher.bin> <key_id.txt>
        cmd = [ENCODER_EXE, "1", "enc", plain_path, cipher_path, keyid_path]
        result = subprocess.run(
            cmd, cwd=td,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        if result.returncode != 0:
            abort(502, f"encoder.exe failed (exit {result.returncode}). "
                       f"stdout:\n{result.stdout}\n\nstderr:\n{result.stderr}")

        if not (os.path.exists(cipher_path) and os.path.exists(keyid_path)):
            abort(502, "Expected outputs not found (cipher.bin/key_id.txt)")

        with open(cipher_path, "rb") as f:
            ct = f.read()
        with open(keyid_path, "r", encoding="utf-8") as f:
            key_id = f.read().strip()
        if not key_id:
            abort(502, "key_id.txt was empty")

    return jsonify({"key_id": key_id, "ciphertext_b64url": b64url_encode(ct)})

# ---------- Decrypt ----------
@app.post("/api/otp/decrypt")
def api_decrypt():
    """
    Request:
      { "key_id": "<...>", "ciphertext_b64url": "<...>" }

    Response:
      { "plaintext_b64url": "<...>", "text": "..."? }  # text only if valid UTF-8
    """
    must_have_encoder()
    body = request.get_json(silent=True) or {}
    key_id = body.get("key_id")
    ct_b64u = body.get("ciphertext_b64url")

    if not key_id or not ct_b64u:
        abort(400, "Provide 'key_id' and 'ciphertext_b64url'")

    try:
        ct = b64url_decode(ct_b64u)
    except Exception:
        abort(400, "Invalid Base64URL in 'ciphertext_b64url'")

    if not ct:
        abort(400, "Ciphertext must be non-empty")
    if len(ct) > MAX_BYTES:
        abort(413, f"Ciphertext too large (max {MAX_BYTES} bytes)")

    with tempfile.TemporaryDirectory() as td:
        cipher_path = os.path.join(td, "cipher.bin")
        keyid_path  = os.path.join(td, "key_id.txt")
        out_path    = os.path.join(td, "plain.out")

        with open(cipher_path, "wb") as f:
            f.write(ct)
        with open(keyid_path, "w", encoding="utf-8") as f:
            f.write(key_id)

        # Your encoder.exe handles KM & XOR back: encoder.exe 1 dec <cipher.bin> <key_id.txt> <output>
        cmd = [ENCODER_EXE, "1", "dec", cipher_path, keyid_path, out_path]
        result = subprocess.run(
            cmd, cwd=td,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        if result.returncode != 0:
            abort(502, f"encoder.exe failed (exit {result.returncode}). "
                       f"stdout:\n{result.stdout}\n\nstderr:\n{result.stderr}")

        if not os.path.exists(out_path):
            abort(502, "Expected output not found (plain.out)")

        with open(out_path, "rb") as f:
            pt = f.read()

    resp = {"plaintext_b64url": b64url_encode(pt)}
    try:
        resp["text"] = pt.decode("utf-8")
    except UnicodeDecodeError:
        pass
    return jsonify(resp)

if __name__ == "__main__":
    print("SCRIPT_DIR         =", SCRIPT_DIR)
    print("Resolved ENCODER_EXE =", ENCODER_EXE, "exists:", bool(ENCODER_EXE and os.path.exists(ENCODER_EXE)))
    app.run(host="127.0.0.1", port=int(os.environ.get("PORT", "2021")), debug=False)