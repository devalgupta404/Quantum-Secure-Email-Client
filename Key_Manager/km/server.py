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
    key_bytes = bytes.fromhex(key_hex)
    return Response(key_bytes, mimetype = "application/octet-stream")



if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8080)
