# Quantum Secure Email Client - API Routes Documentation

## Overview
This document provides a comprehensive overview of all API routes and endpoints for the Quantum Secure Email Client microservices architecture.

## Service Architecture

```
quantum.pointblank.club
├── /api/*           → Backend API (Port 5001)
├── /auth/*          → Authentication Service (Port 2023)
├── /key-manager/*   → Key Manager Service (Port 2020)
├── /otp/*           → OTP Server (Port 2021)
├── /aes/*           → AES Server (Port 2022)
├── /health          → Health Check
└── /                → Status Page
```



---

## 1. Backend API Service (Port 5001)
**Technology**: .NET Core 9.0  
**Base Path**: `/api/*`

### Authentication Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/api/auth/login` | User login | `{email, password}` | `{token, user}` |
| POST | `/api/auth/register` | User registration | `{email, password, name}` | `{token, user}` |
| POST | `/api/auth/refresh` | Refresh JWT token | `{refreshToken}` | `{token}` |
| POST | `/api/auth/logout` | User logout | `{token}` | `{message}` |
| GET | `/api/auth/verify` | Verify token | `Authorization: Bearer {token}` | `{valid, user}` |

### User Management Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/api/user/profile` | Get user profile | - | `{user}` |
| PUT | `/api/user/profile` | Update user profile | `{name, email}` | `{user}` |
| POST | `/api/user/change-password` | Change password | `{currentPassword, newPassword}` | `{message}` |
| DELETE | `/api/user/account` | Delete account | `{password}` | `{message}` |

### Email Management Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/api/emails` | Get all emails | `?page=1&limit=20` | `{emails, pagination}` |
| GET | `/api/emails/{id}` | Get specific email | - | `{email}` |
| POST | `/api/emails/send` | Send email | `{to, subject, body, encryption}` | `{messageId}` |
| POST | `/api/emails/reply` | Reply to email | `{emailId, body}` | `{messageId}` |
| POST | `/api/emails/forward` | Forward email | `{emailId, to, message}` | `{messageId}` |
| PUT | `/api/emails/{id}/read` | Mark as read | - | `{message}` |
| PUT | `/api/emails/{id}/unread` | Mark as unread | - | `{message}` |
| DELETE | `/api/emails/{id}` | Delete email | - | `{message}` |
| POST | `/api/emails/{id}/archive` | Archive email | - | `{message}` |

### Encryption Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/api/encryption/generate-key` | Generate encryption key | `{type}` | `{keyId}` |
| GET | `/api/encryption/keys` | Get user keys | - | `{keys}` |
| POST | `/api/encryption/encrypt` | Encrypt content | `{content, keyId, algorithm}` | `{encrypted}` |
| POST | `/api/encryption/decrypt` | Decrypt content | `{encrypted, keyId}` | `{decrypted}` |

### Configuration Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/api/config/email-providers` | Get email providers | - | `{providers}` |
| POST | `/api/config/email-provider` | Configure email provider | `{provider, settings}` | `{message}` |
| GET | `/api/config/encryption-settings` | Get encryption settings | - | `{settings}` |
| PUT | `/api/config/encryption-settings` | Update encryption settings | `{algorithm, keySize}` | `{message}` |

### Health & Monitoring Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/api/health` | Service health check | - | `{status, services}` |
| GET | `/api/metrics` | Service metrics | - | `{metrics}` |
| GET | `/api/status` | Detailed status | - | `{status, uptime, version}` |

---

## 2. Authentication Service (Port 2023)
**Technology**: Python Flask  
**Base Path**: `/auth/*`

### Core Authentication Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/auth/login` | User authentication | `{email, password}` | `{accessToken, refreshToken, user}` |
| POST | `/auth/register` | User registration | `{email, password, name}` | `{accessToken, refreshToken, user}` |
| POST | `/auth/logout` | User logout | `{refreshToken}` | `{message}` |
| POST | `/auth/refresh` | Refresh access token | `{refreshToken}` | `{accessToken}` |

### Token Management Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/auth/verify-token` | Verify JWT token | `{token}` | `{valid, payload}` |
| POST | `/auth/revoke-token` | Revoke token | `{token}` | `{message}` |
| GET | `/auth/token-info` | Get token information | `Authorization: Bearer {token}` | `{payload, expires}` |

### Password Management Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/auth/forgot-password` | Request password reset | `{email}` | `{message}` |
| POST | `/auth/reset-password` | Reset password | `{token, newPassword}` | `{message}` |
| POST | `/auth/change-password` | Change password | `{currentPassword, newPassword}` | `{message}` |

### User Management Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/auth/user` | Get current user | `Authorization: Bearer {token}` | `{user}` |
| PUT | `/auth/user` | Update user profile | `{name, email}` | `{user}` |
| DELETE | `/auth/user` | Delete user account | `{password}` | `{message}` |

### Security Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/auth/2fa/enable` | Enable 2FA | `{secret}` | `{qrCode}` |
| POST | `/auth/2fa/verify` | Verify 2FA code | `{code}` | `{valid}` |
| POST | `/auth/2fa/disable` | Disable 2FA | `{password}` | `{message}` |
| GET | `/auth/sessions` | Get active sessions | - | `{sessions}` |
| DELETE | `/auth/sessions/{id}` | Terminate session | - | `{message}` |

### Health Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/auth/health` | Service health | - | `{status, uptime}` |

---

## 3. Key Manager Service (Port 2020)
**Technology**: Python Flask  
**Base Path**: `/key-manager/*`

### Key Generation Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/key-manager/generate` | Generate new key | `{algorithm, keySize}` | `{keyId, publicKey}` |
| POST | `/key-manager/generate-quantum` | Generate quantum key | `{algorithm}` | `{keyId, publicKey}` |
| POST | `/key-manager/generate-hybrid` | Generate hybrid key | `{quantumAlg, classicalAlg}` | `{keyId, publicKey}` |

### Key Storage Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/key-manager/store` | Store key | `{keyId, privateKey, metadata}` | `{message}` |
| GET | `/key-manager/retrieve/{keyId}` | Retrieve key | - | `{key, metadata}` |
| PUT | `/key-manager/update/{keyId}` | Update key metadata | `{metadata}` | `{message}` |
| DELETE | `/key-manager/delete/{keyId}` | Delete key | - | `{message}` |

### Key Management Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/key-manager/keys` | List all keys | `?user={userId}` | `{keys}` |
| GET | `/key-manager/keys/{keyId}` | Get key details | - | `{key, metadata}` |
| POST | `/key-manager/import` | Import external key | `{key, format, metadata}` | `{keyId}` |
| POST | `/key-manager/export/{keyId}` | Export key | `{format}` | `{key}` |

### Key Exchange Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/key-manager/exchange/initiate` | Initiate key exchange | `{recipientId, keyId}` | `{exchangeId}` |
| POST | `/key-manager/exchange/complete` | Complete key exchange | `{exchangeId, response}` | `{sharedKey}` |
| GET | `/key-manager/exchange/status/{exchangeId}` | Get exchange status | - | `{status, details}` |

### Quantum-Specific Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/key-manager/quantum/generate-kyber` | Generate Kyber key | `{securityLevel}` | `{keyId, publicKey}` |
| POST | `/key-manager/quantum/generate-dilithium` | Generate Dilithium key | `{securityLevel}` | `{keyId, publicKey}` |
| POST | `/key-manager/quantum/generate-sphincs` | Generate SPHINCS+ key | `{securityLevel}` | `{keyId, publicKey}` |

### Health Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/key-manager/health` | Service health | - | `{status, keysCount}` |

---

## 4. OTP Server (Port 2021)
**Technology**: Python Flask  
**Base Path**: `/otp/*`

### OTP Generation Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/otp/generate-key` | Generate OTP key | `{length}` | `{keyId, key}` |
| POST | `/otp/generate-random` | Generate random OTP | `{length}` | `{otp}` |
| POST | `/otp/generate-time-based` | Generate TOTP | `{keyId, timeWindow}` | `{otp}` |

### OTP Encryption Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/otp/encrypt` | Encrypt with OTP | `{message, keyId}` | `{encrypted}` |
| POST | `/otp/decrypt` | Decrypt with OTP | `{encrypted, keyId}` | `{decrypted}` |
| POST | `/otp/encrypt-file` | Encrypt file with OTP | `{file, keyId}` | `{encryptedFile}` |
| POST | `/otp/decrypt-file` | Decrypt file with OTP | `{encryptedFile, keyId}` | `{decryptedFile}` |

### OTP Validation Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/otp/validate` | Validate OTP | `{otp, keyId}` | `{valid}` |
| POST | `/otp/verify-time-based` | Verify TOTP | `{otp, keyId, timeWindow}` | `{valid}` |

### OTP Management Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/otp/keys` | List OTP keys | - | `{keys}` |
| GET | `/otp/keys/{keyId}` | Get key details | - | `{key, metadata}` |
| DELETE | `/otp/keys/{keyId}` | Delete OTP key | - | `{message}` |

### Health Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/otp/health` | Service health | - | `{status, keysCount}` |

---

## 5. AES Server (Port 2022)
**Technology**: Python Flask  
**Base Path**: `/aes/*`

### AES Key Management Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/aes/generate-key` | Generate AES key | `{keySize}` | `{keyId, key}` |
| POST | `/aes/generate-key-from-password` | Generate key from password | `{password, salt}` | `{keyId, key}` |
| GET | `/aes/keys` | List AES keys | - | `{keys}` |
| DELETE | `/aes/keys/{keyId}` | Delete AES key | - | `{message}` |

### AES Encryption Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/aes/encrypt` | Encrypt with AES | `{message, keyId, mode}` | `{encrypted, iv}` |
| POST | `/aes/decrypt` | Decrypt with AES | `{encrypted, keyId, iv, mode}` | `{decrypted}` |
| POST | `/aes/encrypt-gcm` | Encrypt with AES-GCM | `{message, keyId}` | `{encrypted, tag, nonce}` |
| POST | `/aes/decrypt-gcm` | Decrypt with AES-GCM | `{encrypted, keyId, tag, nonce}` | `{decrypted}` |

### AES File Operations Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| POST | `/aes/encrypt-file` | Encrypt file | `{file, keyId, mode}` | `{encryptedFile}` |
| POST | `/aes/decrypt-file` | Decrypt file | `{encryptedFile, keyId, mode}` | `{decryptedFile}` |
| POST | `/aes/encrypt-file-gcm` | Encrypt file with GCM | `{file, keyId}` | `{encryptedFile}` |
| POST | `/aes/decrypt-file-gcm` | Decrypt file with GCM | `{encryptedFile, keyId}` | `{decryptedFile}` |

### AES Mode Support Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/aes/modes` | Get supported modes | - | `{modes}` |
| POST | `/aes/encrypt-cbc` | Encrypt with AES-CBC | `{message, keyId}` | `{encrypted, iv}` |
| POST | `/aes/decrypt-cbc` | Decrypt with AES-CBC | `{encrypted, keyId, iv}` | `{decrypted}` |
| POST | `/aes/encrypt-ctr` | Encrypt with AES-CTR | `{message, keyId}` | `{encrypted, nonce}` |
| POST | `/aes/decrypt-ctr` | Decrypt with AES-CTR | `{encrypted, keyId, nonce}` | `{decrypted}` |

### Health Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/aes/health` | Service health | - | `{status, keysCount}` |

---

## 6. Health Check Endpoint
**Path**: `/health`

### Health Check Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/health` | Overall system health | - | `{status, services, timestamp}` |

---

## 7. Status Page
**Path**: `/`

### Status Page Routes
| Method | Endpoint | Description | Request Body | Response |
|--------|----------|-------------|--------------|----------|
| GET | `/` | Service status page | - | HTML page with service information |

---

## Request/Response Examples

### Example: Send Encrypted Email
```bash
# 1. Generate encryption key
curl -X POST https://quantum.pointblank.club/key-manager/generate \
  -H "Content-Type: application/json" \
  -d '{"algorithm": "kyber", "keySize": 1024}'

# 2. Encrypt email content
curl -X POST https://quantum.pointblank.club/aes/encrypt-gcm \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello World", "keyId": "key123"}'

# 3. Send encrypted email
curl -X POST https://quantum.pointblank.club/api/emails/send \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer {token}" \
  -d '{"to": "user@example.com", "subject": "Encrypted Email", "body": "{encrypted}", "encryption": "aes-gcm"}'
```

### Example: User Authentication Flow
```bash
# 1. Register user
curl -X POST https://quantum.pointblank.club/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "secure123", "name": "John Doe"}'

# 2. Login user
curl -X POST https://quantum.pointblank.club/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "user@example.com", "password": "secure123"}'

# 3. Use access token for API calls
curl -X GET https://quantum.pointblank.club/api/user/profile \
  -H "Authorization: Bearer {accessToken}"
```

---

## Error Handling

All services return consistent error responses:

```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable error message",
    "details": "Additional error details",
    "timestamp": "2024-01-01T00:00:00Z"
  }
}
```

### Common Error Codes
- `400` - Bad Request
- `401` - Unauthorized
- `403` - Forbidden
- `404` - Not Found
- `409` - Conflict
- `422` - Validation Error
- `500` - Internal Server Error
- `503` - Service Unavailable

---

## Rate Limiting

All services implement rate limiting:
- **Authentication**: 5 requests/minute per IP
- **Key Generation**: 10 requests/minute per user
- **Encryption**: 100 requests/minute per user
- **Email**: 50 requests/minute per user

---

## Security Considerations

1. **HTTPS Only**: All endpoints require HTTPS
2. **JWT Authentication**: Most endpoints require valid JWT tokens
3. **Input Validation**: All inputs are validated and sanitized
4. **Rate Limiting**: Prevents abuse and DoS attacks
5. **CORS**: Configured for specific origins
6. **Headers**: Security headers included in all responses
