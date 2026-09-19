#!/bin/bash
#
# SCRIPT : update_lxcs.sh
# OBJECTIF : Mettre à jour tous les conteneurs LXC en cours d'exécution
#
# ==============================================================================

LOGFILE="/var/log/update_lxcs_cron.log"
EXCLUDED_CTIDS="" # CTIDs à exclure (séparés par des espaces)

exec 1>>$LOGFILE 2>&1

echo "=================================================="
echo "Démarrage de la mise à jour des LXC le $(date)"
echo "=================================================="

# Commandes internes pour le conteneur
UPDATE_COMMAND="export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 && \
                apt-get update -y && \
                apt-get full-upgrade -y && \
                apt-get autoremove -y && \
                apt-get clean && \
                snap refresh 2>/dev/null || true"

REBOOT_CHECK_COMMAND="[ -f /var/run/reboot-required ] && echo 'REBOOT_YES' || echo 'REBOOT_NO'"

# Boucle sur les conteneurs en cours d'exécution
for CTID in $(/usr/sbin/pct list | grep running | awk '{print $1}')
do
    if [[ " $EXCLUDED_CTIDS " =~ " $CTID " ]]; then
        echo "    [SKIP] Conteneur $CTID exclu."
        continue
    fi

    echo "--> Traitement du conteneur CTID $CTID..."

    # 2. Exécution des mises à jour
    echo "    - Exécution des mises à jour..."
    /usr/sbin/pct exec $CTID -- bash -c "$UPDATE_COMMAND"

    if [ $? -ne 0 ]; then
        echo "    [ERREUR CRITIQUE] La mise à jour du conteneur $CTID a échoué. Poursuite vers le prochain LXC."
        continue
    fi

    # 3. Vérification du besoin de redémarrage
    echo "    - Vérification du besoin de redémarrage..."
    REBOOT_CHECK_OUTPUT=$(/usr/sbin/pct exec $CTID -- bash -c "$REBOOT_CHECK_COMMAND")

    if [[ "$REBOOT_CHECK_OUTPUT" == *"REBOOT_YES"* ]]; then

        echo "    [ALERTE] Redémarrage nécessaire pour le conteneur $CTID. Redémarrage en cours..."

        # 4. Redémarrage direct (pct reboot)
        /usr/sbin/pct reboot $CTID --timeout 120

        echo "    [OK] Redémarrage du conteneur $CTID terminé."

    else
        echo "    [OK] Conteneur $CTID mis à jour avec succès. Aucun redémarrage critique nécessaire."
    fi

done

echo "=================================================="
echo "Fin de la mise à jour des LXC le $(date)"
echo "=================================================="

exec 1>&- 2>&-
