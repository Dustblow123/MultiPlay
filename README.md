# Conquête des Tables (nom de code : MultiPlay)

Shoot'em up spatial en pixel art, joué à la manette Xbox, où chaque tir est un
calcul. Un moteur d'apprentissage par répétition espacée décide **quoi**
demander ; le jeu décide **comment** le présenter. Public : enfants de 8 ans et
plus, tables de 1 à 10.

Le document de conception complet est dans
[`docs/Conquete_des_Tables_Document_de_conception.pdf`](docs/Conquete_des_Tables_Document_de_conception.pdf).
Les règles du moteur telles qu'implémentées sont résumées dans
[`docs/moteur_apprentissage.md`](docs/moteur_apprentissage.md).

## État du projet

Feuille de route (§10.2 du document) :

1. **Moteur d'apprentissage seul, validé par simulation** — fait.
2. **Prototype jouable minimal** (vaisseau, ennemis porteurs d'un calcul,
   4 canons, formes grises) — fait, avec en plus la roue de chargement, la
   décomposition, le hub, la carte galactique, les boss (barre de vie, trois
   phases), l'arène (score, records), les déblocages (ailes-trophées,
   équipage, cosmétiques en poussière d'étoile) et l'écran parent, en version
   brute.
3. Test avec un enfant — à faire.
4. à 8. Roue et défense, carte et déblocages, graphismes et sons, systèmes
   suivants, finitions — partiellement couverts en version brute, à reprendre
   avec de vrais assets.

## Lancer le jeu

Prérequis : [Godot 4.5](https://godotengine.org/download) (version standard,
GDScript).

```sh
godot --path .            # lance le jeu (menu des profils)
godot -e --path .         # ouvre le projet dans l'éditeur
```

Résolution de base 640×360, mise à l'échelle entière, filtrage désactivé.

### Commandes

Toutes les commandes passent par l'Input Map de Godot (actions abstraites), le
clavier reste disponible en secours.

| Action | Manette Xbox | Clavier |
| --- | --- | --- |
| Tirer avec un canon (QCM) | A / B / X / Y | A / B / X / Y |
| Choisir un chiffre sur la roue | Stick droit | — |
| Ajouter le chiffre choisi | RT (ou RB) | Espace / Entrée, ou touches 0 à 9 |
| Tirer le nombre composé (roue) | A | A |
| Effacer le nombre composé | LT (ou LB) | Retour arrière |
| Déplacer le vaisseau | Stick gauche / croix | Flèches gauche et droite |
| Menus : choisir | Croix ou stick gauche haut/bas | Flèches haut/bas |
| Menus : valider / retour | A / B | Entrée ou Espace / Échap |
| Options : régler une valeur | Croix ou stick gauche gauche/droite | Flèches gauche/droite |
| Pause | Start | Échap |
| Écran parent (depuis le hub) | Back | P |

Les menus sont sondés avec détection de front et répétition temporisée
(`game/ui/menu_nav.gd`) : un stick incliné ne fait qu'un pas, puis répète
lentement si on le maintient, et doit revenir au neutre à l'ouverture d'un
écran. Les gâchettes (RT, LT) sont des axes et sont traitées de la même façon
dans les missions.

La manette débranchée met le jeu en pause ; il reprend au rebranchement. La
zone morte du stick (avec une roue de test), les vibrations et les sons se
règlent dans l'écran Options du hub et sont enregistrés dans le profil.

Les effets sonores sont des ondes carrées et triangulaires générées en code au
démarrage (`game/autoload/sfx.gd`) : aucun asset audio pour l'instant.

## Architecture en trois couches

```
engine/        Moteur d'apprentissage : logique pure, aucune dépendance au graphisme
  fact.gd              fait canonique (3×7 et 7×3 sont le même fait)
  fact_state.gd        état d'un fait : état, boîte, échéance, historique, confusions
  distractors.gd       distracteurs du QCM par ordre de priorité
  learning_engine.gd   sessions, prochain calcul, résultat, journal rejouable
  engine_config.gd     tous les seuils réglables
persistence/   Profils : un fichier JSON par enfant dans user://profiles
game/          Jeu : demande le prochain calcul, renvoie le résultat
  autoload/game.gd     profil courant, session, manette, sauvegarde
  main.gd / hub.gd     choix du profil, vaisseau-mère et carte galactique
  mission/mission.gd   vaisseau, ennemis, canons, roue, décomposition, boss, arène
  mission/crew.gd      équipage recruté sur les boss, astuces en mission
  mission/ship_view.gd dessin du vaisseau : coque, ailes-trophées, autocollant
  ui/                  résultats, écran parent, options, vaisseau et cosmétiques, navigation
  autoload/sfx.gd      effets rétro générés en code
tests/         Tests unitaires, simulation d'élèves fictifs, test de fumée
```

Interface du moteur (§4.10) :

```gdscript
var engine := LearningEngine.new()
engine.start_session(day)                      # jour = nombre de jours depuis l'époque
var item := engine.next_item({"type": "defense"})   # fait, orientation, mode, options, temps cible
engine.report_result(item, given_answer, time_ms)   # juste/faux, rapide/lent, changement d'état
engine.end_session()
```

Le jeu ne prend aucune décision pédagogique : il relaie `next_item` et
`report_result`. Tout changement d'état découle d'une entrée du journal brut,
et l'état complet peut être recalculé depuis ce journal
(`LearningEngine.rebuild_from_journal`).

## Tests

```sh
sh tests/lint.sh                                         # garde-fou GDScript (voir ci-dessous)
godot --headless --path . --import                       # une fois, après un clone
godot --headless --path . -s tests/run_tests.gd          # unitaires + simulation (≈ 5 s)
godot --headless --path . -s tests/run_tests.gd -- --quick
godot --headless --path . res://tests/smoke/smoke.tscn   # test de fumée du prototype
godot --headless --path . -s tests/simulation/diagnose.gd -- 70 1.0 100   # outil de réglage
```

La simulation fait jouer des élèves fictifs qui oublient selon une courbe
exponentielle (deux missions de 20 calculs par session, une session par jour).
Résultats actuels, sur 55 faits :

| Élève | 90 % de la galaxie colonisée | Tout colonisé au moins une fois |
| --- | --- | --- |
| Moyen | session 26 | session 51 |
| Lent, avec 4 confusions persistantes | session 36 | — (plateau à 50–53) |
| Rapide | session 16 | — |

Les élèves gardent 3 % de fautes d'inattention : une erreur sur un fait maîtrisé
le renvoie en boîte 1 (règle du document), d'où un régime stable à 90–95 % de
planètes colonisées plutôt que 100 % en permanence. Une absence de deux
semaines ne provoque pas d'avalanche (10 révisions au plus par session).

L'intégration continue (`.github/workflows/tests.yml`) exécute ces commandes.

Piège connu de Godot 4.5 : `var x := conteneur[clé]` sur un conteneur non typé
bloque le chargement du script sans message. `tests/lint.sh` refuse ce motif ;
il suffit d'écrire le type (`var x: String = ...`).

## Questions ouvertes (§10.3)

- Les ×0 font-ils partie du jeu ? Réglable : `EngineConfig.include_zero`.
- Tables au-delà de 10 ? Réglable : `EngineConfig.table_max`.
- Boss des tables de 3 et 6 : proposés en version brute, « Le Trèfle » (×3,
  le double plus une fois le nombre) et « La Ruche » (×6, le double de ×3).
- Mode tower defense calme : l'indice `mode_hint = "qcm"` du contexte permet
  déjà de forcer le QCM sur les faits en consolidation.
- Seuils chiffrés (2 s de marge, 400 ms anti-hasard, 20 % d'erreurs) : dans
  `engine/engine_config.gd`, à valider en test réel.
- Titre définitif du jeu.

## Licences des assets

Voir [`CREDITS.md`](CREDITS.md). Le prototype n'utilise aucun asset externe.
