# Scripts de mise à jour Proxmox (VMs & LXC)

Ce dépôt propose deux scripts Bash pensés pour les nœuds Proxmox VE. Ils permettent d'automatiser proprement la mise à jour des machines virtuelles (VMs) et des conteneurs LXC basés sur Debian/Ubuntu, avec un système de simulation (dry-run), de gestion des redémarrages et de notifications push via Gotify.

Retrouvez le guide complet et mes autres services sur la page dédiée du wiki BlablaLinux (https://wiki.blablalinux.be/fr/script-update-lxc-vm-proxmox).

---

## Fonctionnalités

- Simulation intelligente : Vérifie le nombre de paquets APT en attente avant de lancer les modifications (apt-get full-upgrade).
- Gestion des redémarrages : Détecte si un redémarrage est nécessaire (/var/run/reboot-required) et l'effectue proprement (arrêt gracieux avec fallback sur un arrêt forcé si besoin).
- Mode test manuel : Possibilité de cibler une seule VM ou un seul conteneur en passant son ID en argument.
- Rapports Gotify : Envoi d'une notification push structurée avec le statut de l'opération (succès, nombre de machines mises à jour, liste des redémarrages ou erreurs éventuelles).

---

## Contenu du dépôt

- update_vms.sh : Script de mise à jour pour les machines virtuelles (utilise qm).
- update_lxcs.sh : Script de mise à jour pour les conteneurs LXC (utilise pct).

---

## Configuration

Avant d'utiliser les scripts, éditez-les pour renseigner l'URL de votre serveur Gotify ainsi que votre token d'application :

- GOTIFY_URL="https://gotify.votre-domaine.tld"
- GOTIFY_TOKEN="VOTRE_TOKEN_GOTIFY"

Vous pouvez également exclure certaines machines ou conteneurs en renseignant leurs IDs dans la variable correspondante :
- EXCLUDED_VMS="100 102"

---

## Utilisation

### Exécution manuelle (sur toutes les machines)
- sudo ./update_vms.sh
- sudo ./update_lxcs.sh

### Exécution en mode test (sur une machine spécifique)
- sudo ./update_vms.sh 105
- sudo ./update_lxcs.sh 201

### Automatisation via Cron
Vous pouvez planifier l'exécution automatique des scripts via une tâche cron sur votre hôte Proxmox (par exemple tous les matins) :

- 0 6 * * * /chemin/vers/update_vms.sh
- 0 7 * * * /chemin/vers/update_lxcs.sh

---

> Auteur : ce guide est proposé par Amaury aka BlablaLinux. Retrouvez l'ensemble de mes services sur blablalinux.be/mes-services-publics/
