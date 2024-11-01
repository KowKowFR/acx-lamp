
---

# ACX Project

Le **ACX Project** est un script Bash conçu pour automatiser l’installation, la configuration, et la gestion d'un environnement LAMP complet (Linux, Apache, MySQL, PHP), adapté aux projets web et applications nécessitant un hébergement sur Docker avec une gestion des utilisateurs, des quotas de stockage et des connexions SFTP sécurisées.

## Présentation du projet

Ce projet facilite l'installation et la maintenance d'un serveur web en centralisant toutes les opérations dans un script unique. Voici quelques éléments clés du projet :

### Logo ASCII

```
 █████╗  ██████╗██╗  ██╗              ██╗      █████╗ ███╗   ███╗██████╗ 
██╔══██╗██╔════╝╚██╗██╔╝              ██║     ██╔══██╗████╗ ████║██╔══██╗
███████║██║      ╚███╔╝     █████╗    ██║     ███████║██╔████╔██║██████╔╝
██╔══██║██║      ██╔██╗     ╚════╝    ██║     ██╔══██║██║╚██╔╝██║██╔═══╝ 
██║  ██║╚██████╗██╔╝ ██╗              ███████╗██║  ██║██║ ╚═╝ ██║██║     
╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝              ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝                                                                              
```

### Fonctionnalités

- **Environnement LAMP complet** : installe et configure Apache, MySQL, PHP, et phpMyAdmin.
- **Déploiement avec Docker Compose** : simplifie le démarrage, le redémarrage, et l'arrêt des services.
- **Gestion des utilisateurs et des quotas** : applique des limites de stockage aux utilisateurs définis pour Apache et MySQL.
- **Accès sécurisé SFTP** : permet une gestion de fichiers sécurisée pour les utilisateurs distants.
- **Scripts de maintenance** : simplifie les tâches d'administration courantes comme la correction des permissions et les sauvegardes.
- **Automatisation des permissions** : vérifie et corrige régulièrement les permissions d'accès via une tâche cron.
  
## Prérequis

- Serveur sous **Debian** ou une distribution **Ubuntu** compatible.
- **Accès root** requis pour exécuter le script d'installation.
- **Docker** et **Docker Compose** seront installés automatiquement si nécessaire.

## Installation

1. Clonez le dépôt et accédez au répertoire :

   ```
   git clone https://github.com/KowKowFR/acx-lamp
   cd acx-lamp
   ```

2. Rendez le script exécutable et exécutez-le avec les droits root :

   ```
   chmod +x acx-install.sh
   sudo ./acx-install.sh
   ```

   Le script :
   - Installe les dépendances nécessaires, y compris Docker, Docker Compose, et les outils de gestion de quotas.
   - Configure un fichier `.env` pour les variables d'environnement.
   - Crée un certificat SSH pour l'accès SFTP.
   - Définit les permissions et planifie une tâche cron pour vérifier et corriger les droits d'accès.

3. **Configuration initiale** : Pendant l'installation, vous serez invité à définir le nom du projet et quelques options de configuration. Les informations d'identification générées (par exemple, mots de passe) seront enregistrées dans le fichier `credentials.txt`.

## Configuration du fichier `.env`

Le fichier `.env`, généré dans le répertoire du projet, contient les configurations principales :

```env
PROJECT_NAME=acx_project
MYSQL_ROOT_PASSWORD=<mdp_root>
MYSQL_DATABASE=<nom_db>
MYSQL_USER=<utilisateur_db>
MYSQL_PASSWORD=<mdp_utilisateur_db>
SFTP_PORT=3333
HTTP_PORT=8080
HTTPS_PORT=8443
PMA_PORT=9090
```

Vous pouvez modifier ces valeurs pour personnaliser votre environnement. Par exemple, changez `HTTP_PORT` ou `HTTPS_PORT` si vous avez des conflits de ports.

## Utilisation des Scripts de Maintenance

Le script `maintenance.sh` offre des commandes pratiques pour gérer les services et effectuer des tâches de maintenance :

```
./maintenance.sh start       # Démarrer les services Docker
./maintenance.sh stop        # Arrêter les services Docker
./maintenance.sh restart     # Redémarrer les services Docker
./maintenance.sh permissions # Corriger les permissions des répertoires
./maintenance.sh backup      # Sauvegarder la base de données et les fichiers du projet
```

Chaque commande utilise Docker Compose pour gérer les services, rendant les opérations rapides et uniformes.

### Accès aux Services

- **Site Web** : 
  - HTTP : `http://votre_ip_serveur:<HTTP_PORT>`
  - HTTPS : `https://votre_ip_serveur:<HTTPS_PORT>`
- **phpMyAdmin** : Accessible via `http://votre_ip_serveur:<PMA_PORT>` avec les identifiants MySQL du fichier `credentials.txt`.
- **SFTP** : 
  - Hôte : `votre_ip_serveur`
  - Port : `<SFTP_PORT>`
  - Utilisateur et mot de passe : voir `credentials.txt`.

Ces informations sont générées automatiquement et stockées pour référence rapide.

### Sauvegardes

Les sauvegardes régulières sont essentielles pour préserver vos données. Le script `backup` crée des copies de sécurité des bases de données MySQL et des fichiers de site. Les fichiers de sauvegarde sont stockés dans le répertoire `backups/`, avec un horodatage pour chaque sauvegarde.

```
./maintenance.sh backup
```

### Sécurité et Permissions

- Les mots de passe et certificats générés sont uniques à chaque installation, et seuls les ports nécessaires sont ouverts via le pare-feu UFW.
- Le script de correction des permissions est exécuté automatiquement via une tâche cron pour éviter les problèmes d'accès dus aux modifications des utilisateurs ou des fichiers.

## Désinstallation

Pour supprimer le projet et toutes ses configurations :

1. Arrêtez les services Docker :

   ```
   docker-compose down
   ```

2. Supprimez le répertoire du projet et les données associées :

   ```
   rm -rf /root/<nom_du_projet>
   ```

**Remarque** : Assurez-vous de sauvegarder tous les fichiers critiques avant de désinstaller, notamment ceux dans le dossier `backups/`.

## FAQ

### Comment changer le port SFTP après installation ?

Modifiez la variable `SFTP_PORT` dans le fichier `.env`, puis redémarrez les services :

```
./maintenance.sh restart
```

### Puis-je ajouter un nouveau service Docker dans le projet ?

Oui, ajoutez le service à `docker-compose.yml`, puis redémarrez avec :

```
./maintenance.sh restart
```

### Que faire en cas d’erreurs de permissions ?

Exécutez le correcteur de permissions pour résoudre les problèmes d’accès aux fichiers :

```
./maintenance.sh permissions
```

## Contributions

Les contributions sont bienvenues ! Veuillez ouvrir une issue pour proposer des améliorations, signaler des bugs, ou suggérer des fonctionnalités.

@KowKowFR
@Xavito240

---

