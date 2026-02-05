# 🔐 ZK-AUTH Backend - CORRECTED VERSION

Backend Django REST pour le système d'authentification ZK-AUTH utilisant les preuves à divulgation nulle de connaissance (protocole Schnorr sur courbe secp256k1).

## ✨ Nouvelles fonctionnalités (Version corrigée)

### Sécurité post-authentification
- **TokenSession** : Gestion avancée des sessions avec expiration
- **Refresh tokens** : Renouvellement automatique des tokens
- **Inactivity timeout** : Déconnexion après 30 min d'inactivité
- **Device fingerprinting** : Détection de changement d'appareil
- **Session revocation** : Révocation instantanée des sessions compromises

### Gestion multi-appareils
- **Limite de 3 appareils** par utilisateur
- **Liste des appareils actifs** lors de l'enrollment
- **Révocation sélective** d'appareils

### Sauvegarde & Restauration
- **Endpoint backup-fragment** : Sauvegarde du fragment B sur le serveur
- **Endpoint restore-fragment** : Récupération pour restauration de compte
- **Vérification email** pour la restauration

## 📁 Structure du Projet

```
zkauth_backend/
├── zkauth_project/              # Projet Django principal
│   ├── settings.py
│   ├── urls.py
│   ├── wsgi.py
│   └── asgi.py
│
├── authentication/              # Application d'authentification
│   ├── models.py                # Models corrigés (TokenSession, KeyBackup)
│   ├── views.py                 # API endpoints (nouvelles routes)
│   ├── serializers.py           # REST serializers
│   ├── crypto_utils.py          # Vérification Schnorr
│   ├── urls.py                  # Routes (8 nouveaux endpoints)
│   └── admin.py                 # Admin Django
│
├── manage.py
├── requirements.txt
└── README.md
```

## 🆕 Nouveaux Endpoints API

### Session Management

#### 1. Verify Token
```bash
POST /api/auth/verify-token/
Headers: Authorization: Bearer <token>
```

**Réponse :**
```json
{
  "success": true,
  "valid": true,
  "expires_at": "2026-02-05T12:00:00Z",
  "user": {...}
}
```

#### 2. Refresh Token
```bash
POST /api/auth/refresh-token/
{
  "refresh_token": "..."
}
```

**Réponse :**
```json
{
  "success": true,
  "access_token": "new_token_here",
  "expires_at": "2026-02-05T12:00:00Z"
}
```

#### 3. Logout
```bash
POST /api/auth/logout/
Headers: Authorization: Bearer <token>
```

### Backup & Restore

#### 4. Save Backup Fragment
```bash
POST /api/auth/backup-fragment/
{
  "username": "johndoe",
  "fragment": "encrypted_fragment_b",
  "fragment_type": "B"
}
```

#### 5. Restore Fragment
```bash
POST /api/auth/restore-fragment/
{
  "username": "johndoe",
  "email": "john@example.com"
}
```

**Réponse :**
```json
{
  "success": true,
  "fragment_b": "encrypted_data...",
  "created_at": "2026-02-02T10:00:00Z"
}
```

## ⚙️ Installation

### 1️⃣ Prérequis

- Python 3.8+
- PostgreSQL 12+
- pip et virtualenv

### 2️⃣ Installation

```bash
# 1. Environnement virtuel
python3 -m venv venv
source venv/bin/activate  # Linux/Mac
# ou
venv\Scripts\activate  # Windows

# 2. Dépendances
pip install -r requirements.txt

# 3. Configuration PostgreSQL
sudo -u postgres psql
CREATE DATABASE zkauth_db;
CREATE USER zkauth_user WITH PASSWORD 'zkauth_password';
GRANT ALL PRIVILEGES ON DATABASE zkauth_db TO zkauth_user;
\q

# 4. Configuration .env
cp .env.example .env
# Modifier .env avec vos paramètres

# 5. Migrations
python manage.py makemigrations
python manage.py migrate

# 6. Créer superuser
python manage.py createsuperuser

# 7. Lancer le serveur
python manage.py runserver 0.0.0.0:8000
```

## 🔒 Sécurité

### Nouvelles protections implémentées

1. **Session Management**
   - Expiration automatique après 24h
   - Inactivity timeout (30 min)
   - Token rotation avec refresh tokens
   - Révocation instantanée

2. **Multi-Device Limit**
   - Maximum 3 appareils simultanés
   - Tracé de tous les appareils enrôlés
   - Révocation sélective

3. **Post-Authentication Security**
   - Vérification continue du token
   - Détection de changement d'IP (log only)
   - Device fingerprinting
   - Audit complet de toutes les sessions

4. **Backup Security**
   - Fragment B chiffré côté serveur
   - Vérification email pour restauration
   - Traçabilité des accès aux fragments

## 📊 Modèles de données (Nouveaux)

### TokenSession
```python
- token: CharField (unique, indexed)
- refresh_token: CharField (unique)
- expires_at: DateTimeField
- last_activity: DateTimeField (auto-updated)
- is_revoked: BooleanField
- ip_address: GenericIPAddressField
- user_agent: TextField
- device_fingerprint: CharField
```

### KeyBackup
```python
- user: OneToOneField(ZKAuthUser)
- fragment_a_location: CharField (default='google_drive')
- fragment_b_location: CharField (default='zk_auth_cloud')
- fragment_b_encrypted: TextField (stored on server)
- created_at: DateTimeField
- last_verified: DateTimeField
```

## 🧪 Tests

```bash
# Test complet du flux avec session management

# 1. Inscription
curl -X POST http://localhost:8000/api/auth/register/ \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","email":"test@test.com","phone":"+229"}'

# 2. Enrôlement
curl -X POST http://localhost:8000/api/auth/enroll/ \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","public_key":"04..."}'

# 3. Challenge
curl http://localhost:8000/api/auth/challenge/?username=testuser

# 4. Authentification (reçoit access_token + refresh_token)
curl -X POST http://localhost:8000/api/auth/authenticate/ \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","proof":{...}}'

# 5. Vérifier token
curl -X POST http://localhost:8000/api/auth/verify-token/ \
  -H "Authorization: Bearer <access_token>"

# 6. Refresh token
curl -X POST http://localhost:8000/api/auth/refresh-token/ \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"..."}'

# 7. Logout
curl -X POST http://localhost:8000/api/auth/logout/ \
  -H "Authorization: Bearer <access_token>"
```

## 📄 Licence

MIT License

## 👨‍💻 Auteur

**Clovis HOUNLELOU**  
Master en Sécurité Informatique  
IFRI, Université d'Abomey-Calavi, Bénin
