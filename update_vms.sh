#!/bin/bash
#
# SCRIPT : update_vms.sh
# OBJECTIF : Mettre à jour toutes les VMs Debian/Ubuntu en cours d'exécution via QEMU Guest Agent
# AUTEUR : Amaury aka BlablaLinux
# ==============================================================================

LOGFILE="/var/log/update_vms_cron.log"
EXCLUDED_VMS="" # IDs de VMs à exclure (séparés par des espaces)

# Redirection de la sortie vers le log
exec 1>>$LOGFILE 2>&1

echo "=================================================="
echo "Démarrage de la mise à jour des VMs le $(date)"
echo "=================================================="

# Commandes internes pour la VM
# 1. dpkg --configure -a : Répare une interruption précédente
# 2. --force-confdef / --force-confold : Garde tes configs actuelles sans poser de questions
UPDATE_COMMAND="export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 && \
                dpkg --configure -a && \
                apt-get update -y && \
                apt-get full-upgrade -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" && \
                apt-get autoremove -y && \
                apt-get clean && \
                snap refresh 2>/dev/null || true"

REBOOT_CHECK_COMMAND="[ -f /var/run/reboot-required ] && echo 'REBOOT_YES' || echo 'REBOOT_NO'"

# Boucle sur les VMs en cours d'exécution
for VMID in $(/usr/sbin/qm list | grep running | awk '{print $1}')
do
    if [[ " $EXCLUDED_VMS " =~ " $VMID " ]]; then
        echo "    [SKIP] VM $VMID exclue."
        continue
    fi

    echo "--> Traitement de la VM VMID $VMID..."

    # 2. Exécution des mises à jour (Timeout augmenté à 1800s / 30min)
    echo "    - Exécution des mises à jour..."
    /usr/sbin/qm guest exec $VMID --timeout 1800 /bin/bash -- -c "$UPDATE_COMMAND"

    if [ $? -ne 0 ]; then
        echo "    [ERREUR CRITIQUE] La mise à jour de la VM $VMID a échoué (Timeout ou erreur interne). Poursuite vers la prochaine VM."
        continue
    fi

    # 3. Vérification du besoin de redémarrage
    echo "    - Vérification du besoin de redémarrage..."
    REBOOT_CHECK_OUTPUT=$(/usr/sbin/qm guest exec $VMID --timeout 60 /bin/bash -- -c "$REBOOT_CHECK_COMMAND")

    if [[ "$REBOOT_CHECK_OUTPUT" == *"REBOOT_YES"* ]]; then

        echo "    [ALERTE] Redémarrage nécessaire pour la VM $VMID. Redémarrage en cours..."

        # 4. Redémarrage sécurisé
        echo "    - Arrêt de la VM $VMID (shutdown)..."
        /usr/sbin/qm shutdown $VMID --timeout 120

        if /usr/sbin/qm status $VMID | grep -q running; then
            echo "    - Arrêt gracieux échoué. Forçage de l'arrêt (stop)..."
            /usr/sbin/qm stop $VMID
            sleep 5
        fi

        echo "    - Démarrage de la VM $VMID..."
        /usr/sbin/qm start $VMID
        echo "    [OK] Redémarrage de la VM $VMID terminé."

    else
        echo "    [OK] VM $VMID mise à jour avec succès. Aucun redémarrage critique nécessaire."
    fi

done

echo "=================================================="
echo "Fin de la mise à jour des VMs le $(date)"
echo "=================================================="

exec 1>&- 2>&-
