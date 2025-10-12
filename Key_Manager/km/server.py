from flask import Flask, request, make_response, abort, Response
import os, time, binascii
import uuid, json

app = Flask(__name__)

# In-memory store: key_id -> bytes
STORE_FILE = "key_store.json"

def load_store():
    if os.path.exists(STORE_FILE):
        with open(STORE_FILE, "r") as f:
            try:
                return json.load(f)
            except:
                return {}
    return {}

def save_store():
    with open(STORE_FILE, "w") as f:
        json.dump(KEY_STORE, f)

KEY_STORE = load_store()


@app.get("/otp/keys")
def new_key():
    size = int(request.args.get("size", 0))
    key = os.urandom(size)
    key_id = "K" + str(int(time.time() * 1000)) + "-" + uuid.uuid4().hex[:8]
    KEY_STORE[key_id] = key.hex()
    save_store()  # <-- NEW: save it immediately

    response = make_response(key)
    response.headers["X-Key-Id"] = key_id
    return response

@app.get("/otp/keys/<key_id>")
def get_key_by_id(key_id):
    key_hex = KEY_STORE.get(key_id)
    if not key_hex:
        return "Not found", 404

    # FIXED: Return raw bytes instead of JSON
    key_bytes = bytes.fromhex(key_hex)
    response = make_response(key_bytes)
    response.headers["Content-Type"] = "application/octet-stream"
    return response

@app.get("/health")
def health_check():
    """Health check endpoint for Docker/Kubernetes"""
    key_count = len(KEY_STORE)
    store_exists = os.path.exists(STORE_FILE)

    return json.dumps({
        "status": "healthy",
        "service": "key-manager",
        "version": "1.0",
        "metrics": {
            "stored_keys": key_count,
            "store_file_exists": store_exists
        }
    }), 200, {"Content-Type": "application/json"}

if __name__ == "__main__":
    app.run(host="127.0.0.1", port=2020)
