#!/usr/bin/env python3
"""
Quantum Secure Email Client - Authentication Service
Handles user authentication, JWT token management, and user registration.
"""

from flask import Flask, request, jsonify, make_response
import jwt
import bcrypt
import psycopg2
import psycopg2.extras
import os
from datetime import datetime, timedelta
from functools import wraps
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)

# Configuration
JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'your-super-secret-jwt-key-here')
JWT_ISSUER = os.getenv('JWT_ISSUER', 'QuMail')
JWT_AUDIENCE = os.getenv('JWT_AUDIENCE', 'QuMail-Users')
JWT_EXPIRES_MINUTES = int(os.getenv('JWT_EXPIRES_MINUTES', '60'))

# Database configuration
DB_HOST = os.getenv('DB_HOST', 'postgres')
DB_PORT = os.getenv('DB_PORT', '5437')
DB_NAME = os.getenv('DB_NAME', 'quantum_auth')
DB_USERNAME = os.getenv('DB_USERNAME', 'postgres')
DB_PASSWORD = os.getenv('DB_PASSWORD', 'quantum_secure_password_2024')

def get_db_connection():
    """Get database connection"""
    try:
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USERNAME,
            password=DB_PASSWORD
        )
        return conn
    except Exception as e:
        logger.error(f"Database connection error: {e}")
        raise

def token_required(f):
    """Decorator to require valid JWT token"""
    @wraps(f)
    def decorated(*args, **kwargs):
        token = None
        
        # Check for token in Authorization header
        if 'Authorization' in request.headers:
            auth_header = request.headers['Authorization']
            try:
                token = auth_header.split(" ")[1]  # Bearer TOKEN
            except IndexError:
                return jsonify({'error': 'Invalid authorization header format'}), 401
        
        if not token:
            return jsonify({'error': 'Token is missing'}), 401
        
        try:
            # Decode JWT token
            data = jwt.decode(
                token, 
                JWT_SECRET_KEY, 
                algorithms=['HS256'],
                issuer=JWT_ISSUER,
                audience=JWT_AUDIENCE
            )
            current_user = data['sub']  # Subject (user email)
        except jwt.ExpiredSignatureError:
            return jsonify({'error': 'Token has expired'}), 401
        except jwt.InvalidTokenError as e:
            return jsonify({'error': f'Invalid token: {str(e)}'}), 401
        
        return f(current_user, *args, **kwargs)
    
    return decorated

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    try:
        conn = get_db_connection()
        conn.close()
        return jsonify({'status': 'healthy', 'service': 'auth'}), 200
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'error': str(e)}), 500

@app.route('/auth/register', methods=['POST'])
def register():
    """Register a new user"""
    try:
        data = request.get_json()
        
        if not data or not all(k in data for k in ('email', 'password', 'name')):
            return jsonify({'error': 'Missing required fields: email, password, name'}), 400
        
        email = data['email'].lower().strip()
        password = data['password']
        name = data['name'].strip()
        
        # Validate email format
        if '@' not in email or '.' not in email:
            return jsonify({'error': 'Invalid email format'}), 400
        
        # Validate password strength
        if len(password) < 8:
            return jsonify({'error': 'Password must be at least 8 characters long'}), 400
        
        # Hash password
        password_hash = bcrypt.hashpw(password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        try:
            # Check if user already exists
            cursor.execute("SELECT id FROM users WHERE email = %s", (email,))
            if cursor.fetchone():
                return jsonify({'error': 'User already exists'}), 409
            
            # Insert new user
            cursor.execute("""
                INSERT INTO users (email, name, password_hash)
                VALUES (%s, %s, %s)
                RETURNING id, email, name, created_at
            """, (email, name, password_hash))
            
            user = cursor.fetchone()
            conn.commit()
            
            logger.info(f"New user registered: {email}")
            return jsonify({
                'success': True,
                'message': 'User registered successfully',
                'user': {
                    'id': str(user['id']),
                    'email': user['email'],
                    'name': user['name'],
                    'created_at': user['created_at'].isoformat()
                }
            }), 201
            
        except psycopg2.IntegrityError:
            return jsonify({'error': 'User already exists'}), 409
        except Exception as e:
            conn.rollback()
            logger.error(f"Registration error: {e}")
            return jsonify({'error': 'Registration failed'}), 500
        finally:
            cursor.close()
            conn.close()
            
    except Exception as e:
        logger.error(f"Registration error: {e}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/auth/login', methods=['POST'])
def login():
    """Authenticate user and return JWT token"""
    try:
        data = request.get_json()
        
        if not data or not all(k in data for k in ('email', 'password')):
            return jsonify({'error': 'Missing email or password'}), 400
        
        email = data['email'].lower().strip()
        password = data['password']
        
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        try:
            # Get user from database
            cursor.execute("""
                SELECT id, email, name, password_hash, created_at
                FROM users WHERE email = %s
            """, (email,))
            
            user = cursor.fetchone()
            if not user:
                return jsonify({'error': 'Invalid credentials'}), 401
            
            # Verify password
            if not bcrypt.checkpw(password.encode('utf-8'), user['password_hash'].encode('utf-8')):
                return jsonify({'error': 'Invalid credentials'}), 401
            
            # Generate JWT token
            payload = {
                'sub': user['email'],  # Subject
                'user_id': str(user['id']),
                'name': user['name'],
                'iat': datetime.utcnow(),  # Issued at
                'exp': datetime.utcnow() + timedelta(minutes=JWT_EXPIRES_MINUTES),  # Expiration
                'iss': JWT_ISSUER,  # Issuer
                'aud': JWT_AUDIENCE  # Audience
            }
            
            token = jwt.encode(payload, JWT_SECRET_KEY, algorithm='HS256')
            
            logger.info(f"User logged in: {email}")
            return jsonify({
                'success': True,
                'token': token,
                'user': {
                    'id': str(user['id']),
                    'email': user['email'],
                    'name': user['name']
                },
                'expires_in': JWT_EXPIRES_MINUTES * 60
            }), 200
            
        except Exception as e:
            logger.error(f"Login error: {e}")
            return jsonify({'error': 'Login failed'}), 500
        finally:
            cursor.close()
            conn.close()
            
    except Exception as e:
        logger.error(f"Login error: {e}")
        return jsonify({'error': 'Internal server error'}), 500

@app.route('/auth/verify', methods=['GET'])
@token_required
def verify_token(current_user):
    """Verify JWT token and return user info"""
    try:
        conn = get_db_connection()
        cursor = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)
        
        cursor.execute("""
            SELECT id, email, name, created_at
            FROM users WHERE email = %s
        """, (current_user,))
        
        user = cursor.fetchone()
        if not user:
            return jsonify({'error': 'User not found'}), 404
        
        cursor.close()
        conn.close()
        
        return jsonify({
            'success': True,
            'user': {
                'id': str(user['id']),
                'email': user['email'],
                'name': user['name'],
                'created_at': user['created_at'].isoformat()
            }
        }), 200
        
    except Exception as e:
        logger.error(f"Token verification error: {e}")
        return jsonify({'error': 'Token verification failed'}), 500

@app.route('/auth/refresh', methods=['POST'])
@token_required
def refresh_token(current_user):
    """Refresh JWT token"""
    try:
        # Generate new JWT token
        payload = {
            'sub': current_user,
            'iat': datetime.utcnow(),
            'exp': datetime.utcnow() + timedelta(minutes=JWT_EXPIRES_MINUTES),
            'iss': JWT_ISSUER,
            'aud': JWT_AUDIENCE
        }
        
        new_token = jwt.encode(payload, JWT_SECRET_KEY, algorithm='HS256')
        
        return jsonify({
            'success': True,
            'token': new_token,
            'expires_in': JWT_EXPIRES_MINUTES * 60
        }), 200
        
    except Exception as e:
        logger.error(f"Token refresh error: {e}")
        return jsonify({'error': 'Token refresh failed'}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=2023, debug=False)
