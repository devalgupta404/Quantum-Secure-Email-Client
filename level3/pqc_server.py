#!/usr/bin/env python3
"""
Level 3 PQC (Post-Quantum Cryptography) Server
Integrates with the real .NET backend for proper Kyber-512 encryption
Runs on http://127.0.0.1:2023
"""

import json
import requests
from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import sys

app = Flask(__name__)
CORS(app)

# Backend API base URL
BACKEND_URL = "http://localhost:5001/api"

class PQCProxy:
    """Proxy to the real .NET PQC backend"""
    
    def __init__(self):
        self.backend_url = BACKEND_URL
    
    def generate_keypair(self):
        """Generate PQC key pair using real backend"""
        try:
            response = requests.post(f"{self.backend_url}/pqc/generate-keypair", timeout=10)
            if response.status_code == 200:
                data = response.json()
                return {
                    'success': True,
                    'data': data['data']
                }
            else:
                return {
                    'success': False,
                    'error': f"Backend error: {response.status_code} - {response.text}"
                }
        except Exception as e:
            return {
                'success': False,
                'error': f"Backend connection failed: {str(e)}"
            }
    
    def _generate_mock_key(self, size_bytes):
        """Generate mock key of specified size"""
        import base64
        import os
        return base64.b64encode(os.urandom(size_bytes)).decode('utf-8')
    
    def encrypt(self, plaintext, recipient_public_key):
        """Encrypt using real PQC backend"""
        try:
            payload = {
                'plaintext': plaintext,
                'recipientPublicKey': recipient_public_key
            }
            response = requests.post(f"{self.backend_url}/pqc/encrypt", json=payload, timeout=10)
            if response.status_code == 200:
                data = response.json()
                return {
                    'success': True,
                    'data': data['data']
                }
            else:
                return {
                    'success': False,
                    'error': f"Backend error: {response.status_code} - {response.text}"
                }
        except Exception as e:
            return {
                'success': False,
                'error': f"Backend connection failed: {str(e)}"
            }
    
    def _mock_encrypt(self, plaintext):
        """Simple mock encryption"""
        import base64
        import json
        return json.dumps({
            'publicKey': self._generate_mock_key(32),
            'algorithm': 'MockPQC',
            'ciphertext': base64.b64encode(plaintext.encode()).decode()
        })
    
    def decrypt(self, encrypted_body, pqc_ciphertext, private_key):
        """Decrypt using real PQC backend"""
        try:
            payload = {
                'encryptedBody': encrypted_body,
                'pqcCiphertext': pqc_ciphertext,
                'privateKey': private_key
            }
            response = requests.post(f"{self.backend_url}/pqc/decrypt", json=payload, timeout=10)
            if response.status_code == 200:
                data = response.json()
                return {
                    'success': True,
                    'data': data['data']
                }
            else:
                return {
                    'success': False,
                    'error': f"Backend error: {response.status_code} - {response.text}"
                }
        except Exception as e:
            return {
                'success': False,
                'error': f"Backend connection failed: {str(e)}"
            }
    
    def _mock_decrypt(self, encrypted_body):
        """Simple mock decryption"""
        import base64
        import json
        try:
            data = json.loads(encrypted_body)
            if 'ciphertext' in data:
                return base64.b64decode(data['ciphertext']).decode()
            else:
                return "Mock decryption failed"
        except:
            return "Mock decryption failed"

# Initialize PQC proxy
pqc_proxy = PQCProxy()

@app.route('/api/pqc/generate-keypair', methods=['POST'])
def generate_keypair():
    """Generate PQC key pair"""
    try:
        result = pqc_proxy.generate_keypair()
        if result['success']:
            return jsonify(result['data'])
        else:
            return jsonify({'error': result['error']}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/pqc/encrypt', methods=['POST'])
def encrypt():
    """Encrypt message with PQC"""
    try:
        data = request.get_json()
        plaintext = data.get('plaintext', '')
        recipient_public_key = data.get('recipientPublicKey', '')
        
        if not plaintext or not recipient_public_key:
            return jsonify({'error': 'Missing plaintext or recipientPublicKey'}), 400
        
        result = pqc_proxy.encrypt(plaintext, recipient_public_key)
        if result['success']:
            return jsonify(result['data'])
        else:
            return jsonify({'error': result['error']}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/api/pqc/decrypt', methods=['POST'])
def decrypt():
    """Decrypt PQC message"""
    try:
        data = request.get_json()
        encrypted_body = data.get('encryptedBody', '')
        pqc_ciphertext = data.get('pqcCiphertext', '')
        private_key = data.get('privateKey', '')
        
        if not encrypted_body or not pqc_ciphertext or not private_key:
            return jsonify({'error': 'Missing encryptedBody, pqcCiphertext, or privateKey'}), 400
        
        result = pqc_proxy.decrypt(encrypted_body, pqc_ciphertext, private_key)
        if result['success']:
            return jsonify(result['data'])
        else:
            return jsonify({'error': result['error']}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'Level 3 PQC Proxy Server',
        'backend': BACKEND_URL,
        'version': '1.0.0'
    })

@app.route('/', methods=['GET'])
def root():
    """Root endpoint"""
    return jsonify({
        'message': 'Level 3 PQC Proxy Server',
        'endpoints': [
            'POST /api/pqc/generate-keypair',
            'POST /api/pqc/encrypt', 
            'POST /api/pqc/decrypt',
            'GET /health'
        ],
        'backend': BACKEND_URL
    })

if __name__ == '__main__':
    print("🚀 Starting Level 3 PQC Proxy Server...")
    print(f"📡 Backend URL: {BACKEND_URL}")
    print("🔐 Endpoints:")
    print("  POST /api/pqc/generate-keypair")
    print("  POST /api/pqc/encrypt")
    print("  POST /api/pqc/decrypt")
    print("  GET /health")
    print("🌐 Server running on http://127.0.0.1:2023")
    
    app.run(host='127.0.0.1', port=2023, debug=True)
