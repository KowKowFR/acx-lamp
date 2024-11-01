#!/bin/bash

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Fonction de logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERREUR:${NC} $1"
    exit 1
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] ATTENTION:${NC} $1"
}

# Vérification des privilèges root
if [[ $EUID -ne 0 ]]; then
  error "Ce script doit être exécuté en tant que root"
fi

echo -e "
 █████╗  ██████╗██╗  ██╗              ██╗      █████╗ ███╗   ███╗██████╗ 
██╔══██╗██╔════╝╚██╗██╔╝              ██║     ██╔══██╗████╗ ████║██╔══██╗
███████║██║      ╚███╔╝     █████╗    ██║     ███████║██╔████╔██║██████╔╝
██╔══██║██║      ██╔██╗     ╚════╝    ██║     ██╔══██║██║╚██╔╝██║██╔═══╝ 
██║  ██║╚██████╗██╔╝ ██╗              ███████╗██║  ██║██║ ╚═╝ ██║██║     
╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝              ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝     
"

# Demande du nom du projet
read -p "Entrez le nom du projet (lettres minuscules et chiffres uniquement): " PROJECT_NAME

# Validation du nom du projet
if ! [[ $PROJECT_NAME =~ ^[a-z0-9]+$ ]]; then
  error "Le nom du projet ne doit contenir que des lettres minuscules et des chiffres"
fi

# Définition des chemins basés sur le projet
PROJECT_ROOT="/root/${PROJECT_NAME}"
STORAGE_ROOT="/storage/${PROJECT_NAME}"
BASE_PORT=$((2000 + $(echo "$PROJECT_NAME" | md5sum | tr -d -c 0-9 | cut -c 1-3)))
SFTP_PORT=$((BASE_PORT + 22))
HTTP_PORT=$((BASE_PORT + 80))
HTTPS_PORT=$((BASE_PORT + 443))

# Vérification si les ports sont déjà utilisés
if [[ $(netstat -tuln | grep -c ":${SFTP_PORT} ") -ne 0 ]]; then
  error "Le port SFTP ${SFTP_PORT} est déjà utilisé"
fi

if [[ $(netstat -tuln | grep -c ":${HTTP_PORT} ") -ne 0 ]]; then
  error "Le port HTTP ${HTTP_PORT} est déjà utilisé"
fi

if [[ $(netstat -tuln | grep -c ":${HTTPS_PORT} ") -ne 0 ]]; then
  error "Le port HTTPS ${HTTPS_PORT} est déjà utilisé"
fi

# Vérification si le projet existe déjà
if [[ -d $PROJECT_ROOT ]]; then
  warn "Le projet ${PROJECT_NAME} existe déjà. Continuer écrasera les données existantes."
  read -p "Voulez-vous continuer? (o/n): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Oo]$ ]]; then
    exit 0
  fi

  log "Suppression du projet existant..."
  rm -rf $PROJECT_ROOT
fi

# Installation des dépendances
log "Installation des dépendances nécessaires..."
apt-get update
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    quota \
    docker.io \
    docker-compose \
    ufw

# Création des répertoires du projet
log "Création des répertoires pour le projet ${PROJECT_NAME}..."
mkdir -p ${PROJECT_ROOT}/{lamp/www,logs/{apache,mysql},config}
mkdir -p ${STORAGE_ROOT}/mysql

# Génération des variables d'environnement
log "Génération des fichiers de configuration..."

# Génération de mots de passe aléatoires
ROOT_PASS=$(openssl rand -base64 16)
USER_PASS=$(openssl rand -base64 12)
DB_NAME="${PROJECT_NAME}_db"
DB_USER="${PROJECT_NAME}_user"

# Création du fichier .env
cat > ${PROJECT_ROOT}/.env << EOF
PROJECT_NAME=${PROJECT_NAME}
MYSQL_ROOT_PASSWORD=${ROOT_PASS}
MYSQL_DATABASE=${DB_NAME}
MYSQL_USER=${DB_USER}
MYSQL_PASSWORD=${USER_PASS}
SFTP_PORT=${SFTP_PORT}
HTTP_PORT=${HTTP_PORT}
HTTPS_PORT=${HTTPS_PORT}
EOF

# Génération des clés SSH pour SFTP
log "Génération des clés SSH..."
ssh-keygen -t ed25519 -f ${PROJECT_ROOT}/config/ssh_host_ed25519_key -N ""
ssh-keygen -t rsa -b 4096 -f ${PROJECT_ROOT}/config/ssh_host_rsa_key -N ""

# Configuration des permissions
log "Configuration des permissions..."
chmod 600 ${PROJECT_ROOT}/config/ssh_host_ed25519_key
chmod 600 ${PROJECT_ROOT}/config/ssh_host_rsa_key
chmod 644 ${PROJECT_ROOT}/config/ssh_host_ed25519_key.pub
chmod 644 ${PROJECT_ROOT}/config/ssh_host_rsa_key.pub

# Configuration des quotas
log "Configuration des quotas..."

# Ajout des entrées dans /etc/fstab pour les quotas
if ! grep -q "usrquota,grpquota" /etc/fstab; then
    cp /etc/fstab /etc/fstab.backup
    sed -i 's/defaults/defaults,usrquota,grpquota/' /etc/fstab
fi

# Activation des quotas
quotacheck -ugmf /root
quotacheck -ugmf /storage

quotaon -v /root
quotaon -v /storage

# Configuration des quotas utilisateur
setquota -u www-data 2048000 2048000 0 0 /root
setquota -u mysql 8192000 8192000 0 0 /storage

# Configuration des permissions des répertoires
chown -R www-data:www-data ${PROJECT_ROOT}/lamp/www
chown -R www-data:www-data ${PROJECT_ROOT}/logs/apache
chown -R mysql:mysql ${PROJECT_ROOT}/logs/mysql
chown -R mysql:mysql ${STORAGE_ROOT}/mysql
chmod -R 755 ${PROJECT_ROOT}/lamp/www
chmod -R 755 ${PROJECT_ROOT}/logs
chmod -R 700 ${STORAGE_ROOT}/mysql

# Configuration du pare-feu
log "Configuration du pare-feu..."
ufw default deny incoming
ufw default allow outgoing
ufw allow ${HTTP_PORT}/tcp
ufw allow ${HTTPS_PORT}/tcp
ufw allow ${SFTP_PORT}/tcp
ufw allow 22/tcp
ufw --force enable

# Création du docker-compose.yml
log "Création du fichier docker-compose.yml..."
cat > ${PROJECT_ROOT}/docker-compose.yml << EOF
version: '3.8'

services:
  webserver:
    image: php:8.2-apache
    container_name: ${PROJECT_NAME}_webserver
    restart: unless-stopped
    volumes:
      - ./lamp/www:/var/www/html:rw
      - ./logs/apache:/var/log/apache2:rw
    environment:
      - APACHE_DOCUMENT_ROOT=/var/www/html
    ports:
      - "\${HTTP_PORT}:80"
      - "\${HTTPS_PORT}:443"
    networks:
      - ${PROJECT_NAME}_network
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M

  mysql:
    image: mysql:8.0
    container_name: ${PROJECT_NAME}_mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: \${MYSQL_DATABASE}
      MYSQL_USER: \${MYSQL_USER}
      MYSQL_PASSWORD: \${MYSQL_PASSWORD}
    volumes:
      - mysql_data:/var/lib/mysql:rw
      - ./logs/mysql:/var/log/mysql:rw
    networks:
      - ${PROJECT_NAME}_network
    deploy:
      resources:
        limits:
          memory: 1G
        reservations:
          memory: 512M

  phpmyadmin:
    image: phpmyadmin/phpmyadmin
    container_name: ${PROJECT_NAME}_phpmyadmin
    restart: unless-stopped
    environment:
      PMA_HOST: mysql
      MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD}
      PMA_USER: \${MYSQL_USER}
      PMA_PASSWORD: \${MYSQL_PASSWORD}
      UPLOAD_LIMIT: 64M
    ports:
      - "\${PMA_PORT}:80"
    networks:
      - ${PROJECT_NAME}_network
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M

  sftp:
    image: atmoz/sftp
    container_name: ${PROJECT_NAME}_sftp
    volumes:
      - ./lamp/www:/home/\${MYSQL_USER}/www:rw
      - ./config/ssh_host_ed25519_key:/etc/ssh/ssh_host_ed25519_key:ro
      - ./config/ssh_host_rsa_key:/etc/ssh/ssh_host_rsa_key:ro
    ports:
      - "\${SFTP_PORT}:22"
    command: \${MYSQL_USER}:\${MYSQL_PASSWORD}:1001:1001:www
    networks:
      - ${PROJECT_NAME}_network
    deploy:
      resources:
        limits:
          memory: 512M
        reservations:
          memory: 256M

networks:
  ${PROJECT_NAME}_network:
    driver: bridge

volumes:
  mysql_data:
    driver_opts:
      type: none
      device: ${STORAGE_ROOT}/mysql
      o: bind
EOF

# Ajout du port phpMyAdmin dans .env
PMA_PORT=$((BASE_PORT + 8080))
echo "PMA_PORT=${PMA_PORT}" >> ${PROJECT_ROOT}/.env

# Correction des permissions pour le répertoire web
log "Configuration des permissions..."
# Création d'un groupe pour le projet
groupadd ${PROJECT_NAME}_users
useradd -g ${PROJECT_NAME}_users -M -s /sbin/nologin ${DB_USER}
echo "${DB_USER}:${USER_PASS}" | chpasswd

# Configuration des permissions
chmod 755 ${PROJECT_ROOT}
chmod 755 ${PROJECT_ROOT}/lamp
chmod 2775 ${PROJECT_ROOT}/lamp/www  # SetGID bit
chown -R ${DB_USER}:${PROJECT_NAME}_users ${PROJECT_ROOT}/lamp/www
chmod -R g+w ${PROJECT_ROOT}/lamp/www

# Script pour corriger les permissions automatiquement
cat > ${PROJECT_ROOT}/fix-permissions.sh << 'EOF'
#!/bin/bash
PROJECT_PATH="$1"
if [ -z "$PROJECT_PATH" ]; then
    echo "Usage: $0 /chemin/vers/projet"
    exit 1
fi

# Correction des permissions
find "${PROJECT_PATH}/lamp/www" -type d -exec chmod 2775 {} \;
find "${PROJECT_PATH}/lamp/www" -type f -exec chmod 0664 {} \;
EOF

chmod +x ${PROJECT_ROOT}/fix-permissions.sh

# Ajout d'une tâche cron pour vérifier les permissions
echo "*/15 * * * * root ${PROJECT_ROOT}/fix-permissions.sh ${PROJECT_ROOT} >/dev/null 2>&1" > /etc/cron.d/${PROJECT_NAME}_permissions

# Mise à jour du fichier maintenance.sh
cat > ${PROJECT_ROOT}/maintenance.sh << EOF
#!/bin/bash
# Script de maintenance pour ${PROJECT_NAME}

display_menu() {
    clear
    echo "=============================="
    echo "    Panel de Maintenance"
    echo "=============================="
    echo "1. Démarrer les services"
    echo "2. Arrêter les services"
    echo "3. Redémarrer les services"
    echo "4. Corriger les permissions"
    echo "5. Sauvegarder"
    echo "6. Afficher les credentials"
    echo "0. Quitter"
    echo "=============================="
    echo -n "Choisissez une option (0-6): "
}

while true; do
    display_menu
    read -r choice  # Lecture de l'option choisie

    case $choice in
        1)
            echo "Démarrage des services..."
            docker-compose up -d
            echo "Services démarrés."
            ;;
        2)
            echo "Arrêt des services..."
            docker-compose down
            echo "Services arrêtés."
            ;;
        3)
            echo "Redémarrage des services..."
            docker-compose restart
            echo "Services redémarrés."
            ;;
        4)
            echo "Correction des permissions..."
            ./fix-permissions.sh "${PROJECT_ROOT}"
            echo "Permissions corrigées."
            ;;
        5)
            echo "Création de la sauvegarde..."
            timestamp=$(date +%Y%m%d_%H%M%S)
            backup_dir="${PROJECT_ROOT}/backups/${timestamp}"
            mkdir -p "$backup_dir"
            docker-compose exec mysql mysqldump -u root -p"${MYSQL_ROOT_PASSWORD}" "${DB_NAME}" > "$backup_dir/database.sql"
            tar -czf "$backup_dir/www.tar.gz" lamp/www/
            echo "Sauvegarde créée dans $backup_dir"
            ;;
        6)
            echo "Affichage des credentials..."
            if [[ -f "${PROJECT_ROOT}/credentials.txt" ]]; then
                cat "${PROJECT_ROOT}/credentials.txt"
            else
                echo "Le fichier credentials.txt est introuvable."
            fi
            ;;
        0)
            echo "Quitter."
            exit 0
            ;;
        *)
            echo "Option invalide. Veuillez choisir une option entre 0 et 6."
            ;;
    esac
    echo -n "Appuyez sur une touche pour continuer..."
    read -r -n 1
done
EOF

chmod +x ${PROJECT_ROOT}/maintenance.sh

# Mise à jour du fichier credentials.txt pour inclure phpMyAdmin
cat > ${PROJECT_ROOT}/credentials.txt << EOF
Projet: ${PROJECT_NAME}

Base de données:
  Host: localhost
  Database: ${DB_NAME}
  Username: ${DB_USER}
  Password: ${USER_PASS}

SFTP:
  Host: votre_ip_serveur
  Port: ${SFTP_PORT}
  Username: ${DB_USER}
  Password: ${USER_PASS}

Site Web:
  HTTP: http://votre_ip_serveur:${HTTP_PORT}
  HTTPS: https://votre_ip_serveur:${HTTPS_PORT}

phpMyAdmin:
  URL: http://votre_ip_serveur:${PMA_PORT}
  Username: ${DB_USER}
  Password: ${USER_PASS}
EOF

chmod 600 ${PROJECT_ROOT}/credentials.txt

# Création d'un fichier index.html de test
cat > ${PROJECT_ROOT}/lamp/www/index.html << EOF
<!DOCTYPE html>
<html>
<head>
    <title>${PROJECT_NAME} - Site Web Test</title>
</head>
<body>
    <h1>Bienvenue sur le site ${PROJECT_NAME}!</h1>
    <p>Si vous voyez cette page, votre stack LAMP est correctement configuré.</p>
</body>
</html>
EOF

# Démarrage des services
log "Démarrage des services Docker..."
cd ${PROJECT_ROOT}
docker-compose up -d

chown ${DB_USER}:${DB_USER}s ${PROJECT_ROOT}/lamp/www/
chown ${DB_USER}:${DB_USER}+"s" ${PROJECT_ROOT}/lamp/*
chown ${DB_USER}:${DB_USER}+"s" ${PROJECT_ROOT}/lamp/
chmod 777 ${PROJECT_ROOT}/
chmod 777 ${PROJECT_ROOT}/lamp/*
chmod 777 ${PROJECT_ROOT}/lamp/www/
chmod 777 ${PROJECT_ROOT}/lamp/www/*
log "PERMISSION OK"


# Affichage des informations de connexion
log "Installation terminée avec succès!"
echo -e "\n${GREEN}Informations de connexion pour ${PROJECT_NAME}:${NC}"
echo -e "Base de données:"
echo -e "  Host: localhost"
echo -e "  Database: ${DB_NAME}"
echo -e "  Username: ${DB_USER}"
echo -e "  Password: ${USER_PASS}"
echo -e "\nSFTP:"
echo -e "  Host: votre_ip_serveur"
echo -e "  Port: ${SFTP_PORT}"
echo -e "  Username: ${DB_USER}"
echo -e "  Password: ${USER_PASS}"
echo -e "\nSite Web:"
echo -e "  HTTP: http://votre_ip_serveur:${HTTP_PORT}"
echo -e "  HTTPS: https://votre_ip_serveur:${HTTPS_PORT}"
echo -e "\nphpMyAdmin:"
echo -e "  URL: http://votre_ip_serveur:${PMA_PORT}"
echo -e "  Username: ${DB_USER}"
echo -e "  Password: ${USER_PASS}"
echo -e "\n${YELLOW}IMPORTANT: Sauvegardez ces informations dans un endroit sûr!${NC}"

log "Les informations de connexion ont été sauvegardées dans ${PROJECT_ROOT}/credentials.txt"
EOF

