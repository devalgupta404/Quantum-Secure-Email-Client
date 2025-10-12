#!/usr/bin/env python3
"""
Standalone PQC (Post-Quantum Cryptography) Server
Provides basic Kyber-512 key generation and encryption endpoints
Runs on http://127.0.0.1:2023
"""

import json
import base64
import random
import string
from flask import Flask, request, jsonify
from flask_cors import CORS
import os
import sys

app = Flask(__name__)
CORS(app)

# Mock PQC implementation (simplified)
class MockPQC:
    def __init__(self):
        self.key_pairs = {}  # Store key pairs in memory
    
    def generate_key_pair(self):
        """Generate a mock PQC key pair"""
        # Generate random keys (in real implementation, this would use Kyber-512)
        public_key = self._generate_random_key(32)  # 32 bytes = 256 bits
        private_key = self._generate_random_key(32)
        
        key_id = f"PQC_{len(self.key_pairs)}"
        self.key_pairs[key_id] = {
            'public_key': public_key,
            'private_key': private_key
        }
        
        return {
            'keyId': key_id,
            'publicKey': public_key,
            'privateKey': private_key
        }
    
    def encrypt(self, plaintext, recipient_public_key):
        """Mock PQC encryption"""
        # In real implementation, this would use Kyber encapsulation
        # For now, we'll do simple XOR encryption with the public key
        plaintext_bytes = plaintext.encode('utf-8')
        key_bytes = base64.b64decode(recipient_public_key)
        
        # Pad key if needed
        while len(key_bytes) < len(plaintext_bytes):
            key_bytes += key_bytes
        
        # XOR encryption
        ciphertext_bytes = bytes(a ^ b for a, b in zip(plaintext_bytes, key_bytes))
        ciphertext = base64.b64encode(ciphertext_bytes).decode('utf-8')
        
        return {
            'pqcCiphertext': ciphertext,
            'encryptedBody': {
                'algorithm': 'MockPQC',
                'ciphertext': ciphertext,
                'publicKey': recipient_public_key
            }
        }
    
    def decrypt(self, encrypted_body, pqc_ciphertext, private_key):
        """Mock PQC decryption"""
        try:
            # Get the public key from encrypted body
            public_key = encrypted_body.get('publicKey', '')
            if not public_key:
                raise ValueError("No public key in encrypted body")
            
            # Decrypt using XOR (reverse of encryption)
            ciphertext_bytes = base64.b64decode(pqc_ciphertext)
            key_bytes = base64.b64decode(public_key)
            
            # Pad key if needed
            while len(key_bytes) < len(ciphertext_bytes):
                key_bytes += key_bytes
            
            # XOR decryption
            plaintext_bytes = bytes(a ^ b for a, b in zip(ciphertext_bytes, key_bytes))
            plaintext = plaintext_bytes.decode('utf-8')
            
            return plaintext
        except Exception as e:
            raise ValueError(f"Decryption failed: {str(e)}")
    
    def _generate_random_key(self, length):
        """Generate a random base64-encoded key"""
        random_bytes = os.urandom(length)
        return base64.b64encode(random_bytes).decode('utf-8')

# Initialize PQC service
pqc_service = MockPQC()

@app.route('/api/pqc/generate-keypair', methods=['POST'])
def generate_keypair():
    """Generate a new PQC key pair"""
    try:
        key_pair = pqc_service.generate_key_pair()
        return jsonify({
            'success': True,
            'data': key_pair
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/pqc/encrypt', methods=['POST'])
def encrypt():
    """Encrypt data using PQC"""
    try:
        data = request.get_json()
        plaintext = data.get('plaintext', '')
        recipient_public_key = data.get('recipientPublicKey', '')
        
        if not plaintext or not recipient_public_key:
            return jsonify({
                'success': False,
                'error': 'Missing plaintext or recipientPublicKey'
            }), 400
        
        result = pqc_service.encrypt(plaintext, recipient_public_key)
        return jsonify({
            'success': True,
            'data': result
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/pqc/decrypt', methods=['POST'])
def decrypt():
    """Decrypt data using PQC"""
    try:
        data = request.get_json()
        encrypted_body = data.get('encryptedBody', {})
        pqc_ciphertext = data.get('pqcCiphertext', '')
        private_key = data.get('privateKey', '')
        
        if not encrypted_body or not pqc_ciphertext or not private_key:
            return jsonify({
                'success': False,
                'error': 'Missing encryptedBody, pqcCiphertext, or privateKey'
            }), 400
        
        plaintext = pqc_service.decrypt(encrypted_body, pqc_ciphertext, private_key)
        return jsonify({
            'success': True,
            'data': {
                'plaintext': plaintext
            }
        })
    except Exception as e:
        return jsonify({
            'success': False,
            'error': str(e)
        }), 500

@app.route('/api/pqc/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'OK',
        'service': 'PQC Server',
        'port': 2023
    })

if __name__ == '__main__':
    print("Starting PQC Server on http://127.0.0.1:2023")
    print("Endpoints:")
    print("  POST /api/pqc/generate-keypair")
    print("  POST /api/pqc/encrypt") 
    print("  POST /api/pqc/decrypt")
    print("  GET  /api/pqc/health")
    print()
    
    app.run(host='0.0.0.0', port=2023, debug=False)
