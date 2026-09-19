# Scripts de mise à jour Proxmox (VMs & LXC)

Deux scripts Bash pour automatiser la mise à jour des **machines virtuelles (VMs)** et des **conteneurs LXC** sous **Proxmox VE**, avec prise en charge de Debian et Ubuntu.

Les scripts intègrent notamment un mode simulation, la détection et la gestion des redémarrages nécessaires, ainsi que l'envoi de notifications push via **Gotify**.

## Dépôts

Le projet est disponible sur GitHub et synchronisé sur l'instance Gitea de BlablaLinux.

* **GitHub :** https://github.com/anyblabla/proxmox-update-scripts
* **Gitea :** https://gitea.blablalinux.be/blablalinux/proxmox-update-scripts

🌐 **Autres services BlablaLinux :**
https://blablalinux.be/mes-services-publics/

---

## Fonctionnalités

* **Mise à jour automatisée** des systèmes Debian/Ubuntu avec `apt-get full-upgrade`.
* **Vérification préalable** du nombre de paquets à mettre à jour afin d'éviter les opérations inutiles.
* **Détection des redémarrages nécessaires** via `/var/run/reboot-required`.
* **Redémarrage propre** des VMs et conteneurs, avec bascule sur un arrêt forcé en cas de besoin.
* **Mode ciblé** permettant de mettre à jour une seule VM ou un seul conteneur en indiquant son ID.
* **Exclusion de machines** grâce à une liste d'IDs configurables.
* **Notifications Gotify** avec un récapitulatif de l'opération :

  * statut global ;
  * nombre de machines mises à jour ;
  * redémarrages effectués ;
  * erreurs éventuelles.

---

## Contenu du dépôt

| Fichier          | Description                                           |
| ---------------- | ----------------------------------------------------- |
| `update_vms.sh`  | Mise à jour des machines virtuelles Proxmox via `qm`. |
| `update_lxcs.sh` | Mise à jour des conteneurs LXC via `pct`.             |

---

## Prérequis

Les scripts sont destinés à être exécutés **directement sur un nœud Proxmox VE**.

Ils nécessitent notamment :

* Proxmox VE ;
* Bash ;
* `qm` pour la gestion des VMs ;
* `pct` pour la gestion des conteneurs LXC ;
* des systèmes invités basés sur Debian ou Ubuntu ;
* un serveur Gotify si les notifications sont utilisées.

Les scripts doivent être exécutés avec les privilèges nécessaires à la gestion des VMs et conteneurs.

---

## Configuration

Avant la première utilisation, éditez les variables de configuration présentes dans les scripts.

### Gotify

Renseignez l'URL de votre serveur Gotify et le token de l'application :

```bash
GOTIFY_URL="https://gotify.votre-domaine.tld"
GOTIFY_TOKEN="VOTRE_TOKEN_GOTIFY"
```

### Exclusion de machines

Il est également possible d'exclure certaines VMs ou certains conteneurs en renseignant leurs IDs.

Par exemple :

```bash
EXCLUDED_VMS="100 102"
```

Les machines concernées seront alors ignorées lors de l'exécution globale du script.

---

## Installation

### Depuis GitHub

```bash
git clone https://github.com/anyblabla/proxmox-update-scripts.git
cd proxmox-update-scripts
```

### Depuis Gitea

```bash
git clone https://gitea.blablalinux.be/blablalinux/proxmox-update-scripts.git
cd proxmox-update-scripts
```

Rendez ensuite les scripts exécutables :

```bash
chmod +x update_vms.sh update_lxcs.sh
```

---

## Utilisation

### Mettre à jour toutes les VMs

```bash
./update_vms.sh
```

### Mettre à jour tous les conteneurs LXC

```bash
./update_lxcs.sh
```

---

### Mettre à jour une seule VM

Indiquez directement son ID Proxmox :

```bash
./update_vms.sh 105
```

### Mettre à jour un seul conteneur LXC

```bash
./update_lxcs.sh 201
```

Ce mode est particulièrement pratique pour effectuer un test manuel avant de mettre en place l'automatisation.

---

## Automatisation avec Cron

Les scripts peuvent être exécutés automatiquement via **Cron** sur votre nœud Proxmox.

Par exemple, pour lancer quotidiennement la mise à jour des VMs à **06:00** et celle des conteneurs LXC à **07:00** :

```cron
0 6 * * * /chemin/vers/update_vms.sh
0 7 * * * /chemin/vers/update_lxcs.sh
```

Pour une exécution avec les privilèges nécessaires, il est recommandé de placer ces tâches dans la crontab de `root` :

```bash
sudo crontab -e
```

---

## Notifications Gotify

Lorsque Gotify est configuré, les scripts envoient un rapport à la fin de l'opération.

Le rapport permet notamment de connaître :

* le résultat global de l'exécution ;
* le nombre de VMs ou LXC traités ;
* les systèmes ayant nécessité un redémarrage ;
* les éventuelles erreurs rencontrées.

Cela permet de laisser tourner les mises à jour automatiquement sans devoir aller vérifier chaque nœud Proxmox à la main.

---

## Documentation

Pour le fonctionnement détaillé des scripts, leur configuration et les différents cas particuliers :

📖 **Wiki BlablaLinux — Mise à jour automatique des VMs et LXC Proxmox**
https://wiki.blablalinux.be/fr/script-update-lxc-vm-proxmox

---

## Auteur

**Amaury — BlablaLinux**

Retrouvez mes autres services publics :

🌐 https://blablalinux.be/mes-services-publics/
