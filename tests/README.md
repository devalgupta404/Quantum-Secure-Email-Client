# QuMail Unit Tests

This folder contains unit tests for the Quantum-Secure-Email-Client (QuMail) project.

## Test Structure

```
tests/
├── python/                    # Python crypto services tests
│   └── test_crypto_services.py
├── dotnet/                    # .NET backend tests
│   └── AuthTests.cs
├── flutter/                   # Flutter frontend tests
│   └── widget_test.dart
└── README.md
```

## Running Tests

### Python Tests (Crypto Services)

```bash
cd tests/python
python -m pytest test_crypto_services.py -v

# Or using unittest
python -m unittest test_crypto_services -v
```

### .NET Tests (Backend)

```bash
cd quantum-secure-email-client
dotnet test
```

### Flutter Tests (Frontend)

```bash
cd frontend
flutter test
```

## Test Coverage

### Python Crypto Services
- **Key Manager**: Key generation, storage, retrieval
- **AES Server**: AES-256-GCM encryption/decryption
- **OTP API**: One-Time Pad generation and usage
- **PQC Server**: CRYSTALS-Kyber encapsulation/decapsulation

### .NET Backend
- **Authentication**: Registration, login, JWT tokens
- **Email Service**: Send, receive, encrypt, decrypt
- **Database**: Connection, CRUD operations

### Flutter Frontend
- **Authentication UI**: Login/registration forms
- **Email UI**: Compose, list, detail views
- **Encryption UI**: Status indicators, key exchange
- **Navigation**: Screen transitions

## Adding New Tests

1. Create test file in appropriate folder
2. Follow existing naming conventions
3. Add test cases with descriptive names
4. Run tests locally before committing

## Dependencies

### Python
```bash
pip install pytest
```

### .NET
```bash
dotnet add package MSTest.TestFramework
dotnet add package MSTest.TestAdapter
```

### Flutter
```bash
flutter pub add --dev flutter_test
```
