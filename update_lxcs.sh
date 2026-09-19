#!/bin/bash
#
# SCRIPT : update_lxcs.sh
# OBJECTIF : Mettre à jour tous les conteneurs LXC Debian/Ubuntu en cours d'exécution
# AUTEUR : Amaury aka BlablaLinux
# ==============================================================================

# --- PARAMÈTRES DE GOTIFY ---
GOTIFY_URL="https://gotify.votre-domaine.tld"
GOTIFY_TOKEN="VOTRE_TOKEN_GOTIFY"

# --- PARAMÈTRES DU SCRIPT ---
LOGFILE="/var/log/update_lxcs_cron.log"
EXCLUDED_CTIDS="" # CTIDs à exclure (séparés par des espaces)
TARGET_CTID="$1" # Optionnel : ./update_lxcs.sh <CTID> pour tester sur un seul LXC (cron = sans argument = tous les LXCs)
SUCCESS_COUNT=0
FAILURE_COUNT=0
UPDATED_CT_COUNT=0 # Nouveau compteur pour les CT qui ont réellement eu des MAJ
REBOOT_LIST=""

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
echo "Démarrage de la mise à jour des LXC le $(date)"
echo "=================================================="

# Commandes internes pour le conteneur
# Simulation de mise à jour APT : compte les paquets à installer/mettre à jour/supprimer
# --allow-releaseinfo-change : évite le blocage silencieux lors d'un changement de suite
# (ex: Debian trixie 13.5 → 13.6), où apt-get update retourne un exit code non-zero
# sans ce flag, coupant le && et renvoyant 0 paquet à tort.
UPDATE_COMMAND_DRY_RUN="export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 && \
                        (apt-get update -y --allow-releaseinfo-change 2>/dev/null && apt-get full-upgrade -s --assume-no 2>/dev/null) | grep -E '^(Inst|Upgr|Remv)' | wc -l"

# Commande réelle de mise à jour (Correction du statut de sortie)
UPDATE_COMMAND_REAL="export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8 && \
                   apt-get update -y --allow-releaseinfo-change && \
                   apt-get full-upgrade -y && \
                   apt-get autoremove -y && \
                   apt-get clean && \
                   STATUS=\$? && \
                   (snap refresh 2>/dev/null || true) && \
                   exit \$STATUS"

REBOOT_CHECK_COMMAND="[ -f /var/run/reboot-required ] && echo 'REBOOT_YES' || echo 'REBOOT_NO'"

# Détermination de la liste des LXCs à traiter
# - Sans argument (usage cron normal) : tous les LXCs en cours d'exécution
# - Avec un CTID en argument (usage test manuel, ex: ./update_lxcs.sh 101) : uniquement ce LXC
if [ -n "$TARGET_CTID" ]; then
    if ! /usr/sbin/pct status "$TARGET_CTID" 2>/dev/null | grep -q running; then
        echo "[ERREUR] LXC $TARGET_CTID introuvable ou non démarré sur ce nœud. Abandon."
        exit 1
    fi
    CT_LIST="$TARGET_CTID"
    echo "--- MODE TEST : exécution limitée au LXC $TARGET_CTID uniquement ---"
else
    CT_LIST=$(/usr/sbin/pct list | grep running | awk '{print $1}')
fi

# Boucle sur les conteneurs ciblés
for CTID in $CT_LIST
do
    if [[ " $EXCLUDED_CTIDS " =~ " $CTID " ]]; then
        echo "    [SKIP] Conteneur $CTID exclu."
        continue
    fi

    echo "--> Traitement du conteneur CTID $CTID..."

    # 1. Vérification s'il y a des mises à jour disponibles (Simulation)
    echo "    - Simulation des mises à jour..."
    APT_UPDATES_COUNT=$(/usr/sbin/pct exec $CTID -- bash -c "$UPDATE_COMMAND_DRY_RUN" 2>/dev/null)
    APT_UPDATES_COUNT=${APT_UPDATES_COUNT//[^0-9]/} # Nettoyage de la sortie pour ne garder que le nombre

    if ! [[ "$APT_UPDATES_COUNT" =~ ^[0-9]+$ ]]; then
        APT_UPDATES_COUNT=0
    fi

    echo "    - $APT_UPDATES_COUNT paquets APT à mettre à jour."

    # 2. Exécution des mises à jour uniquement si nécessaire
    if [ "$APT_UPDATES_COUNT" -gt 0 ]; then

        UPDATED_CT_COUNT=$((UPDATED_CT_COUNT + 1))
        echo "    - Exécution des mises à jour réelles..."

        # Exécution des mises à jour réelles
        /usr/sbin/pct exec $CTID -- bash -c "$UPDATE_COMMAND_REAL"

        if [ $? -ne 0 ]; then
            echo "    [ERREUR CRITIQUE] La mise à jour du conteneur $CTID a échoué. Poursuite vers le prochain LXC."
            FAILURE_COUNT=$((FAILURE_COUNT + 1))
            continue
        fi

        # 3. Vérification du besoin de redémarrage (Uniquement si MAJ effectuée)
        echo "    - Vérification du besoin de redémarrage..."
        REBOOT_CHECK_OUTPUT=$(/usr/sbin/pct exec $CTID -- bash -c "$REBOOT_CHECK_COMMAND")

        if [[ "$REBOOT_CHECK_OUTPUT" == *"REBOOT_YES"* ]]; then
            echo "    [ALERTE] Redémarrage nécessaire pour le conteneur $CTID. Redémarrage en cours..."

            if [ -z "$REBOOT_LIST" ]; then
                REBOOT_LIST="$CTID"
            else
                REBOOT_LIST="$REBOOT_LIST, $CTID"
            fi

            # 4. Redémarrage direct (pct reboot)
            /usr/sbin/pct reboot $CTID --timeout 120

            echo "    [OK] Redémarrage du conteneur $CTID terminé."

        else
            echo "    [OK] Conteneur $CTID mis à jour avec succès. Aucun redémarrage critique nécessaire."
        fi
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "    [SKIP] Aucune mise à jour APT détectée. Conteneur $CTID ignoré."
    fi
done

echo "=================================================="
echo "Fin de la mise à jour des LXC le $(date)"
echo "=================================================="

# --- ENVOI DE LA NOTIFICATION FINALE (TOUJOURS ENVOYÉE) ---
TOTAL_CT_PROCESSED=$((SUCCESS_COUNT + FAILURE_COUNT))

if [ $FAILURE_COUNT -gt 0 ]; then
    TITLE="❌ LXC Update ÉCHEC(s) sur $HOSTNAME"
    MESSAGE="$FAILURE_COUNT LXC ont rencontré une ERREUR. $SUCCESS_COUNT LXC mis à jour. Redémarrés : $REBOOT_LIST"
    PRIORITY=8
elif [ -n "$REBOOT_LIST" ]; then
    TITLE="⚠️ LXC Update Succès & Redémarrage(s)"
    MESSAGE="$UPDATED_CT_COUNT LXC mis à jour. Redémarrage effectué sur : $REBOOT_LIST"
    PRIORITY=6
elif [ $UPDATED_CT_COUNT -gt 0 ]; then
    TITLE="✅ LXC Update SUCCÈS sur $HOSTNAME"
    MESSAGE="$UPDATED_CT_COUNT LXC mis à jour. Aucun LXC n'a nécessité de redémarrage."
    PRIORITY=4
else
    TITLE="✅ LXC Update — RAS sur $HOSTNAME"
    MESSAGE="Script exécuté avec succès. Aucune mise à jour nécessaire, aucune erreur."
    PRIORITY=2
fi

send_gotify_notification "$TITLE" "$MESSAGE" $PRIORITY
echo "Notification Gotify envoyée (priorité $PRIORITY)."

exec 1>&- 2>&-
exit 0
