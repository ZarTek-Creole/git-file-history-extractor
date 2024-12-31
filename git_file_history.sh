#!/usr/bin/env bash
#
# Script : git_file_history.sh
#
# Objectif :
#   1) Parcourir tout l’historique Git d’un fichier (en suivant les renommages avec -M / -C).
#   2) Extraire la version du fichier pour chaque commit (format : <timestamp>_<commit>_<basename>.md).
#   3) Générer un patch (.patch) pour chaque commit (concernant ce fichier).
#   4) Produire un fichier summary.txt listant : commits, timestamps, messages, chemins extraits...
#   5) (Optionnel) Générer une diff HTML via diff2html (ENABLE_HTML_DIFF=1), si disponible.
#
# Usage :
#   ./git_file_history.sh [fichier]
#
#   - Par défaut, [fichier] = "cdc.md" si aucun paramètre n'est fourni.
#   - Pour afficher l'aide : ./git_file_history.sh --help
#
# Variables d'environnement (optionnelles) :
#   RENAME_THRESHOLD (défaut: 1%) => seuil de détection de renommage, ex: 50% pour -M50%
#   COPY_THRESHOLD   (défaut: 1%) => seuil de détection de copie, ex: 50% pour -C50%
#   ENABLE_HTML_DIFF (défaut: 0)  => mettre à 1 pour activer la génération de diff HTML via diff2html
#
# Exemples :
#   RENAME_THRESHOLD=50% COPY_THRESHOLD=50% ENABLE_HTML_DIFF=1 \
#       ./git_file_history.sh docs/cdc.md
#
# Dépôt GitHub :
#   https://github.com/ZarTek-Creole/git-file-history-extractor
#
# Licence :
#   [Indiquez ici la licence, par ex. MIT, GPL, etc.]
#
# -------------------------------------------------------------------------------------
# Historique des modifications :
#   - Ajout d'une option --help
#   - Ajout de logs plus clairs sur les seuils de renommage/copie
#   - Vérification de diff2html si ENABLE_HTML_DIFF=1
#   - Rappels à l'utilisateur en fin de script
#
# -------------------------------------------------------------------------------------

set -e

############################################
#         CONFIGURATIONS PAR DEFAUT
############################################
FILENAME="${1:-cdc.md}"
RENAME_THRESHOLD="${RENAME_THRESHOLD:-1%}"
COPY_THRESHOLD="${COPY_THRESHOLD:-1%}"
ENABLE_HTML_DIFF="${ENABLE_HTML_DIFF:-0}"

OUTPUT_DIR="versions_of_${FILENAME}"
SUMMARY_FILE="${OUTPUT_DIR}/summary.txt"

############################################
#         GESTION DE L'OPTION --help
############################################
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  echo "Usage : $0 [nom-du-fichier]"
  echo
  echo "Par défaut, 'cdc.md' est utilisé si aucun argument n'est fourni."
  echo "Ce script parcourt l'historique Git pour extraire toutes les versions d'un fichier,"
  echo "génère des patches, un résumé (summary.txt) et (optionnellement) une diff HTML."
  echo
  echo "Variables d'environnement (optionnelles) :"
  echo "  RENAME_THRESHOLD (défaut: 1%) => ex: 50% pour -M50%"
  echo "  COPY_THRESHOLD   (défaut: 1%) => ex: 50% pour -C50%"
  echo "  ENABLE_HTML_DIFF (défaut: 0)  => mettre 1 pour activer diff2html"
  echo
  echo "Exemple :"
  echo "  RENAME_THRESHOLD=50% COPY_THRESHOLD=50% ENABLE_HTML_DIFF=1 \\"
  echo "       $0 docs/cdc.md"
  echo
  echo "Pour plus d'infos : https://github.com/ZarTek-Creole/git-file-history-extractor"
  exit 0
fi

############################################
#         VERIFICATION DEPOT GIT
############################################
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "Erreur : ce script doit être lancé à l'intérieur d'un dépôt Git."
  exit 1
fi

echo "[INFO] Paramètres de détection de renommage : -M${RENAME_THRESHOLD}, -C${COPY_THRESHOLD}"
echo "[INFO] Génération HTML activée ? ENABLE_HTML_DIFF=${ENABLE_HTML_DIFF}"

############################################
#  (Optionnel) Vérifier si diff2html est installé
############################################
DIFF2HTML_AVAILABLE=0
if [ "$ENABLE_HTML_DIFF" -eq 1 ]; then
  if command -v diff2html >/dev/null 2>&1; then
    DIFF2HTML_AVAILABLE=1
    echo "[INFO] diff2html détecté : la génération HTML sera activée."
  else
    echo "[INFO] ENABLE_HTML_DIFF=1 mais diff2html n'est pas disponible. Passage en mode patch uniquement."
  fi
fi

############################################
#  CREATION/RESET DU DOSSIER DE SORTIE
############################################
mkdir -p "${OUTPUT_DIR}"
rm -f "${SUMMARY_FILE}"

############################################
#  1) RECUPERER LA LISTE DES COMMITS
############################################
echo "[INFO] Récupération de la liste des commits pour '${FILENAME}'..."
COMMITS=$(git log --follow -M${RENAME_THRESHOLD} -C${COPY_THRESHOLD} \
               --pretty=format:"%H" --reverse -- "$FILENAME")

# Si aucun commit trouvé
if [ -z "$COMMITS" ]; then
  echo "Aucun commit trouvé concernant le fichier '$FILENAME'."
  exit 0
fi

echo "Liste des commits à analyser (du plus ancien au plus récent) :"
echo "$COMMITS"
echo "-----------------------------------------"

############################################
#  2) PARCOURIR CHAQUE COMMIT
############################################
#     Détecter le chemin effectif,
#     extraire la version, générer le patch,
#     générer le diff HTML, MAJ summary.txt
############################################

current_path="$FILENAME"

for commit in $COMMITS; do
  echo "-----"
  echo "Commit : $commit"

  # Récupérer le timestamp, message, auteur...
  commit_timestamp=$(git show -s --format='%ct' "$commit")
  commit_message=$(git show -s --format='%s' "$commit")
  author_name=$(git show -s --format='%an' "$commit")
  author_email=$(git show -s --format='%ae' "$commit")
  date_human=$(git show -s --format='%cd' --date=format:'%Y-%m-%d %H:%M:%S' "$commit")

  # Comparer ce commit avec son parent pour détecter rename/copy
  DIFF_INFO="$(git diff-tree --no-commit-id --name-status -r -M${RENAME_THRESHOLD} -C${COPY_THRESHOLD} \
                             "${commit}^" "${commit}" 2>/dev/null || true)"

  actual_path_found="false"
  actual_path="$current_path"

  # Parcourir chaque ligne
  while IFS= read -r line; do
    status=$(echo "$line" | awk '{print $1}')  # R100, M, A, C50, etc.
    path1=$(echo "$line" | awk '{print $2}')
    path2=$(echo "$line" | awk '{print $3}')

    case "$status" in
      R*|C*)
        # Ex: R100 old/path/file  new/path/file
        #     C70  old/path/file  new/path/file
        if [[ "$path2" == "$current_path" ]]; then
          actual_path="$path1"
          actual_path_found="true"
        elif [[ "$path1" == "$current_path" ]]; then
          actual_path="$path2"
          actual_path_found="true"
        fi
        ;;
      *)
        # M, A, D...
        if [[ "$path1" == "$current_path" ]]; then
          actual_path_found="true"
          actual_path="$path1"
        fi
        ;;
    esac
  done <<< "$DIFF_INFO"

  # Si pas de rename détecté, on garde le chemin précédent
  if [ "$actual_path_found" != "true" ]; then
    actual_path="$current_path"
  fi

  echo "Chemin retenu pour ce commit : $actual_path"

  # Construire le nom du fichier extrait
  base_name="$(basename "$actual_path" | sed 's|/|_|g')"  # remplacer "/" par "_"
  out_file="${OUTPUT_DIR}/${commit_timestamp}_${commit}_${base_name}.md"

  # Extraire le contenu
  if git show "${commit}:${actual_path}" > "${out_file}" 2>/dev/null; then
    echo "Fichier extrait dans : ${out_file}"
  else
    echo "ATTENTION : Impossible d'extraire « ${actual_path} » pour le commit ${commit}."
    rm -f "${out_file}" 2>/dev/null || true
  fi

  # Générer le patch (diff brut)
  patch_file="${OUTPUT_DIR}/${commit_timestamp}_${commit}_${base_name}.patch"
  git show --patch --format=full "$commit" -- "${actual_path}" > "${patch_file}" 2>/dev/null || true

  # Vérifier si le patch est vide
  if [ ! -s "${patch_file}" ]; then
    echo "ATTENTION : Pas de patch généré pour le commit ${commit} (fichier ${actual_path})."
    rm -f "${patch_file}" 2>/dev/null || true
  else
    echo "Patch généré : ${patch_file}"
  fi

  # (Optionnel) Génération du diff HTML, si diff2html dispo et ENABLE_HTML_DIFF=1
  html_file=""
  if [ "$DIFF2HTML_AVAILABLE" -eq 1 ]; then
    html_file="${OUTPUT_DIR}/${commit_timestamp}_${commit}_${base_name}.html"
    if [ -s "${patch_file}" ]; then
      diff2html -i file -o stdout "${patch_file}" > "${html_file}" 2>/dev/null || true
      if [ -s "${html_file}" ]; then
        echo "Diff HTML généré : ${html_file}"
      else
        rm -f "${html_file}" 2>/dev/null || true
      fi
    fi
  fi

  # Mettre à jour le summary.txt
  {
    echo "Commit         : $commit"
    echo "Timestamp (UTC): $commit_timestamp ($date_human)"
    echo "Auteur         : $author_name <$author_email>"
    echo "Message        : $commit_message"
    echo "Fichier extrait: $out_file"
    echo "Patch          : $patch_file"
    [ -n "$html_file" ] && echo "Diff HTML      : $html_file"
    echo "--------------------------------------------------"
  } >> "${SUMMARY_FILE}"

  # Mettre à jour current_path pour la suite
  current_path="$actual_path"
done

echo "-----------------------------------------"
echo "Extraction terminée !"
echo "Toutes les versions du fichier (avec ses éventuels renommages) se trouvent dans :"
echo "  ${OUTPUT_DIR}/"
echo "Consultez également le fichier summary.txt pour la liste complète :"
echo "  ${SUMMARY_FILE}"
if [ "$ENABLE_HTML_DIFF" -eq 1 ] && [ "$DIFF2HTML_AVAILABLE" -eq 0 ]; then
  echo "[INFO] Pour générer les diffs HTML, installez diff2html (ex: npm install -g diff2html-cli)."
fi
echo "[FIN]"
