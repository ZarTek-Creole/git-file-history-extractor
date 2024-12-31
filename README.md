# Git File History Extractor

> **Script Bash** pour extraire l’historique complet d’un fichier au sein d’un dépôt Git, y compris les renommages et déplacements.  
> Génère un résumé (`summary.txt`), les versions extraites du fichier, ainsi que des patches et (optionnellement) des diffs HTML.

## Fonctionnalités

- **Extraction** de toutes les versions d’un fichier (avec renommage).
- **Création** de fichiers `.patch` pour chaque commit.
- **Génération** d’un récapitulatif complet (`summary.txt`), listant :
  - le commit,  
  - l’auteur,  
  - le message,  
  - la date,  
  - le fichier extrait,  
  - le patch correspondant,  
  - (optionnel) le diff HTML (si `diff2html` est installé).
- **Personnalisation** : ajustement des seuils de détection de renommage (`-M`, `-C`), activation du rendu HTML, etc.

## Installation

1. **Cloner** ce dépôt :  
   ```bash
   git clone https://github.com/ZarTek-Creole/git-file-history-extractor.git
   cd git-file-history-extractor
   ```
2. **Rendre le script exécutable** :  
   ```bash
   chmod +x git_file_history.sh
   ```

## Utilisation

Dans votre dépôt Git :

```bash
# Exemple : extraire l'historique d'un fichier nommé "cdc.md"
./git_file_history.sh cdc.md
```

### Variables d’environnement (optionnelles)

- **RENAME_THRESHOLD** : seuil de détection de renommage, par ex. `50%` (défaut `1%`).  
- **COPY_THRESHOLD** : seuil de détection de copie, par ex. `50%` (défaut `1%`).  
- **ENABLE_HTML_DIFF** : mettre `1` pour générer des diffs HTML (via `diff2html`).  

Exemple d’exécution avec variables personnalisées :

```bash
RENAME_THRESHOLD=50% COPY_THRESHOLD=50% ENABLE_HTML_DIFF=1 ./git_file_history.sh docs/cdc.md
```

## Résultats

- Le script crée un dossier `versions_of_<nomFichier>/` :
  - **Toutes les versions** du fichier, nommées :  
    ```
    <timestamp>_<commit>_<fichier>.md
    ```
  - **Des patches** :  
    ```
    <timestamp>_<commit>_<fichier>.patch
    ```
  - **(Optionnel) des diffs HTML** :  
    ```
    <timestamp>_<commit>_<fichier>.html
    ```
  - Un **fichier `summary.txt`** qui récapitule l’ensemble des commits, les auteurs, les messages, et les chemins des fichiers extraits.

## Exemple rapide

```bash
# Dans le répertoire d'un projet Git
cd /path/to/my-git-repo

# Lancer le script pour extraire l'historique de cdc.md
/path/to/git_file_history_extractor/git_file_history.sh cdc.md

# Regarder le résultat
ls versions_of_cdc.md/
cat versions_of_cdc.md/summary.txt
```
