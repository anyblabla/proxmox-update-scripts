#!/bin/bash
#
# SCRIPT : update_vms.sh
# OBJECTIF : Mettre à jour toutes les VMs Debian/Ubuntu en cours d'exécution
# AUTEUR : Amaury aka BlablaLinux
# ==============================================================================

# --- PARAMÈTRES DE GOTIFY ---
GOTIFY_URL="https://gotify.votre-domaine.tld"
GOTIFY_TOKEN="VOTRE_TOKEN_GOTIFY"

# --- PARAMÈTRES DU SCRIPT ---
LOGFILE="/var/log/update_vms_cron.log"
EXCLUDED_VMS="" # IDs de VMs à exclure (séparés par des espaces)
TARGET_VMID="$1" # Optionnel : ./update_vms.sh <VMID> pour tester sur une seule VM (cron = sans argument = toutes les VMs)
SUCCESS_COUNT=0
FAILURE_COUNT=0
UPDATED_VMS_COUNT=0 # Compteur de VMs qui ont réellement eu des MAJ
REBOOT_LIST=""

# Redirection vers le log
exec 1>>$LOGFILE 2>&1

# --- FONCTION DE NOTIFICATION GOTIFY (MÉTHODE FORM-DATA) ---
send_gotify_notification() {
    local title="$1"
    local message="$2"
    local priority="$3"
    curl -k -s -X POST "$GOTIFY_URL/message?token=$GOTIFY_TOKEN" \
        -F "title=$title" \
        -F "message=$message" \
        -F "priority=$priority" > /dev/null 2>&1
}

echo "=================================================="
echo "Démarrage de la mise à jour des VMs le $(date)"
echo "=================================================="

# Commandes internes pour la VM
# Utilisation d'un préfixe "VAL:" pour isoler le compteur du reste du JSON de qm guest exec
UPDATE_COMMAND_DRY_RUN="export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 && \
                        UPDATES=\$( (apt-get update -y --allow-releaseinfo-change 2>/dev/null && apt-get full-upgrade -s --assume-no 2>/dev/null) | grep -E '^(Inst|Upgr|Remv)' | wc -l ) && \
                        echo \"VAL:\$UPDATES\""

# Correction du statut de sortie pour l'Apt (évite le piège du || true de snap)
UPDATE_COMMAND_REAL="export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 && \
                   dpkg --configure -a && \
                   apt-get update -y --allow-releaseinfo-change && \
                   apt-get full-upgrade -y -o Dpkg::Options::=\"--force-confdef\" -o Dpkg::Options::=\"--force-confold\" && \
                   apt-get autoremove -y && \
                   apt-get clean && \
                   STATUS=\$? && \
                   (snap refresh 2>/dev/null || true) && \
                   exit \$STATUS"

REBOOT_CHECK_COMMAND="[ -f /var/run/reboot-required ] && echo 'REBOOT_YES' || echo 'REBOOT_NO'"

# Détermination de la liste des VMs à traiter
# - Sans argument (usage cron normal) : toutes les VMs en cours d'exécution
# - Avec un VMID en argument (usage test manuel, ex: ./update_vms.sh 168) : uniquement cette VM
if [ -n "$TARGET_VMID" ]; then
    if ! /usr/sbin/qm status "$TARGET_VMID" 2>/dev/null | grep -q running; then
        echo "[ERREUR] VM $TARGET_VMID introuvable ou non démarrée sur ce nœud. Abandon."
        exit 1
    fi
    VM_LIST="$TARGET_VMID"
    echo "--- MODE TEST : exécution limitée à la VM $TARGET_VMID uniquement ---"
else
    VM_LIST=$(/usr/sbin/qm list | grep running | awk '{print $1}')
fi

# Boucle sur les VMs ciblées
for VMID in $VM_LIST
do
    if [[ " $EXCLUDED_VMS " =~ " $VMID " ]]; then
        echo "    [SKIP] VM $VMID exclue."
        continue
    fi

    echo "--> Traitement de la VM VMID $VMID..."

    # 1. Vérification s'il y a des mises à jour disponibles (Simulation)
    echo "    - Simulation des mises à jour..."
    RAW_OUTPUT=$(/usr/sbin/qm guest exec $VMID --timeout 60 /bin/bash -- -c "$UPDATE_COMMAND_DRY_RUN" 2>/dev/null)

    # Extraction ciblée du nombre après "VAL:"
    APT_UPDATES_COUNT=$(echo "$RAW_OUTPUT" | grep -oP 'VAL:\K[0-9]+')

    # S'assurer que le compteur est un nombre valide
    if ! [[ "$APT_UPDATES_COUNT" =~ ^[0-9]+$ ]]; then
        APT_UPDATES_COUNT=0
    fi

    echo "    - $APT_UPDATES_COUNT paquets APT à mettre à jour."

    # Vérification si des mises à jour APT sont nécessaires
    if [ "$APT_UPDATES_COUNT" -gt 0 ]; then

        UPDATED_VMS_COUNT=$((UPDATED_VMS_COUNT + 1))
        echo "    - Exécution des mises à jour réelles..."

        # 2. Exécution des mises à jour réelles, en deux temps : démarrage ASYNCHRONE
        START_OUT=$(/usr/sbin/qm guest exec $VMID --synchronous 0 /bin/bash -- -c "$UPDATE_COMMAND_REAL" 2>&1)
        EXEC_PID=$(echo "$START_OUT" | grep -oP '"pid"\s*:\s*\K[0-9]+')

        if [ -z "$EXEC_PID" ]; then
            echo "    [ERREUR CRITIQUE] Impossible de démarrer la commande de mise à jour sur la VM $VMID."
            echo "    Sortie brute qm guest exec : $START_OUT"
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            continue
        fi

        echo "    - Commande démarrée (PID invité : $EXEC_PID). Attente de la fin d'exécution..."

        EXIT_CODE=""
        STATUS_OUT=""
        ELAPSED=0
        POLL_INTERVAL=5
        MAX_WAIT=1800

        while [ $ELAPSED -lt $MAX_WAIT ]; do
            STATUS_OUT=$(/usr/sbin/qm guest exec-status $VMID $EXEC_PID 2>&1)

            if echo "$STATUS_OUT" | grep -qi "does not exist"; then
                sleep 2
                ELAPSED=$((ELAPSED + 2))
                continue
            fi

            if echo "$STATUS_OUT" | grep -qP '"exited"\s*:\s*1'; then
                EXIT_CODE=$(echo "$STATUS_OUT" | grep -oP '"exitcode"\s*:\s*\K[0-9]+')
                break
            fi

            sleep $POLL_INTERVAL
            ELAPSED=$((ELAPSED + POLL_INTERVAL))
        done

        if [ -z "$EXIT_CODE" ]; then
            echo "    [ERREUR CRITIQUE] Pas de résultat exploitable pour la VM $VMID après ${ELAPSED}s."
            echo "    Dernière sortie qm guest exec-status : $STATUS_OUT"
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            continue
        elif [ "$EXIT_CODE" != "0" ]; then
            echo "    [ERREUR CRITIQUE] La mise à jour de la VM $VMID a échoué (Exit Code: $EXIT_CODE)."
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            continue
        fi

        # 3. Vérification du besoin de redémarrage
        echo "    - Vérification du besoin de redémarrage..."
        REBOOT_CHECK_OUTPUT=$(/usr/sbin/qm guest exec $VMID --timeout 60 /bin/bash -- -c "$REBOOT_CHECK_COMMAND")

        if [[ "$REBOOT_CHECK_OUTPUT" == *"REBOOT_YES"* ]]; then
            echo "    [ALERTE] Redémarrage nécessaire pour la VM $VMID. Redémarrage en cours..."

            if [ -z "$REBOOT_LIST" ]; then
                REBOOT_LIST="$VMID"
            else
                REBOOT_LIST="$REBOOT_LIST, $VMID"
            fi

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
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "    [SKIP] Aucune mise à jour APT détectée. VM $VMID ignorée."
    fi

done

echo "=================================================="
echo "Fin de la mise à jour des VMs le $(date)"
echo "=================================================="

# --- ENVOI DE LA NOTIFICATION FINALE ---
TOTAL_VMS_PROCESSED=$((SUCCESS_COUNT + FAILURE_COUNT))

if [ $FAILURE_COUNT -gt 0 ]; then
    TITLE="❌ VMs Update ÉCHEC(s) sur $HOSTNAME"
    MESSAGE="$FAILURE_COUNT VMs sur $TOTAL_VMS_PROCESSED ont rencontré une ERREUR. $SUCCESS_COUNT VMs mises à jour. Redémarrées : $REBOOT_LIST"
    PRIORITY=8
elif [ -n "$REBOOT_LIST" ]; then
    TITLE="⚠️ VMs Update Succès & Redémarrage(s)"
    MESSAGE="$UPDATED_VMS_COUNT VMs mises à jour. Redémarrage effectué sur : $REBOOT_LIST"
    PRIORITY=6
elif [ $UPDATED_VMS_COUNT -gt 0 ]; then
    TITLE="✅ VMs Update SUCCÈS sur $HOSTNAME"
    MESSAGE="$UPDATED_VMS_COUNT VMs mises à jour. Aucune VM n'a nécessité de redémarrage."
    PRIORITY=4
else
    TITLE="✅ VMs Update — RAS sur $HOSTNAME"
    MESSAGE="Script exécuté avec succès. Aucune mise à jour nécessaire, aucune erreur."
    PRIORITY=2
fi

send_gotify_notification "$TITLE" "$MESSAGE" $PRIORITY
echo "Notification Gotify envoyée (priorité $PRIORITY)."

exec 1>&- 2>&-
exit 0
