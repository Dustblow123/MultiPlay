# Moteur d'apprentissage : règles implémentées

Ce document résume la section 4 du document de conception telle qu'elle est
codée dans `engine/`. Les valeurs chiffrées sont celles de
`engine/engine_config.gd`.

## Le fait

- Forme canonique, petit facteur d'abord : clé `"3x7"` pour 3×7 et 7×3.
- Statistiques gardées par orientation. Si elles divergent (écart de 15 points
  de réussite ou de 800 ms sur la médiane), l'orientation la plus faible est
  présentée dans 70 % des cas.
- Faits triviaux (×0, ×1, ×10) : échauffement en début de session (2 par
  session) et calibration du temps moteur. Ils passent directement au QCM,
  sans présentation.
- Tables 1 à 10 par défaut (55 faits), ×0 et ×11+ réglables.

## Données par fait (`FactState`)

État (nouveau, apprentissage, consolidation, maîtrisé), boîte de Leitner 0 à 5,
prochaine révision (jour et session), 5 dernières tentatives, temps médian
récent, rechutes, confusions (mauvaises réponses et fréquence), statistiques par
orientation, série de réussites en QCM avec les sessions concernées.

## États et modes

| État | Mode de saisie | Passage à l'état suivant |
| --- | --- | --- |
| Nouveau | Présentation (calcul + réponse) | présenté une fois → apprentissage, boîte 1 |
| Apprentissage | QCM, 4 canons | 3 réussites de suite en QCM, sur au moins 2 sessions |
| Consolidation | Roue de chargement | boîte 4 atteinte par une réponse rapide à la roue |
| Maîtrisé | Roue, nuées rapides, décomposition (boss) | erreur → consolidation, boîte 1, rechute comptée |

Le jeu peut forcer le QCM (`mode_hint = "qcm"`) sur un fait en consolidation ou
maîtrisé, et la décomposition (`mode_hint = "decomposition"`) sur un fait
maîtrisé seulement.

## Seuil de rapidité

Temps moteur de base = médiane des 10 derniers temps de réponse corrects sur les
faits triviaux, séparément pour le QCM et la roue (valeurs par défaut avant
3 mesures : 1 200 ms et 2 500 ms). Seuil « rapide » = temps de base + 2 000 ms.

## Règles de passage

- Juste et rapide, lors d'une révision due : +1 boîte.
- Juste mais lent : boîte inchangée.
- Juste hors révision due (entraînement) : boîte et échéance inchangées. Un
  fait servi en entraînement tous les jours n'a pas sa révision repoussée.
- Faux : boîte 1, re-présentation 2 ou 3 calculs plus tard, confusion
  enregistrée, rechute comptée si le fait était maîtrisé.
- Anti-hasard : une réponse QCM en moins de 400 ms, ou signalée comme
  mitraillage par le jeu, est journalisée mais ne change rien.

## Intervalles de révision

Une révision est due quand les deux minimums sont atteints.

| Boîte | Sessions min. | Jours min. |
| --- | --- | --- |
| 1 | même session | 0 |
| 2 | 1 | 1 |
| 3 | 2 | 3 |
| 4 | 3 | 7 |
| 5 | 4 | 21 |

Après une rechute, les jours minimum sont multipliés par 0,75 par rechute (au
moins 1 jour à partir de la boîte 2). Les révisions sont plafonnées à 10 par
session, les plus en retard (retard relatif à l'intervalle) d'abord.

## Composition d'une session

1. Échauffement : 2 faits triviaux.
2. Révisions dues, triées par retard relatif, 10 au plus.
3. 2 ou 3 faits nouveaux, dans l'ordre de découverte des tables
   (×1, ×10, ×2, ×5, puis ×3, ×4, ×9, puis ×6, ×7, ×8), seulement si le taux
   d'erreur des 20 dernières réponses est inférieur à 20 % et si 8 révisions au
   plus sont en attente. Ils sont intercalés entre les révisions.
4. Complément d'entraînement jusqu'à 20 items planifiés : faits en cours puis
   faits maîtrisés les moins récents (ratio connu/nouveau proche de 80/20),
   en privilégiant les faits pas encore demandés dans la session.
5. Au-delà, `next_item` continue à servir des items d'entraînement : la
   longueur de la mission appartient au jeu.
6. Entrelacement : jamais deux fois le même fait d'affilée, 3 passages au plus
   par fait et par session (hors re-présentations après erreur).
7. Anti-frustration : après 2 erreurs consécutives, un fait facile et maîtrisé.

## Distracteurs du QCM

Par ordre de priorité, en tourniquet (un par catégorie puis complément) :
confusions personnelles, voisins dans la table (7×7, 7×9 pour 7×8), voisins de
table (6×8, 8×8), inversion de chiffres (65 pour 56), un facteur de plus ou de
moins (deux pas). Jamais de nombre absurde : positif, au plus 120, pas en
dessous du tiers de la réponse ni au-dessus du triple.

## Contextes de mission

`next_item(context)` accepte :

| Clé | Effet |
| --- | --- |
| `type = "defense"` | sert d'abord les révisions dues de la file |
| `type = "exploration"` | sert d'abord les faits nouveaux et en apprentissage |
| `type = "duel"`, `pair = ["7x8", "6x9"]` | alterne les deux faits confondus (3 passages chacun), puis file normale |
| `type = "arena"` | faits maîtrisés seulement |
| `type = "boss"`, `tables = [7]` | faits maîtrisés de la table |
| `tables = [..]` | filtre les faits par table |
| `fact = "3x4"` | impose un fait précis (point faible d'un boss, tests) |
| `mode_hint` | `"qcm"` ou `"decomposition"` (voir ci-dessus) |

`suggest_mission()` propose au hub : duel si une confusion est encore active
(une fois par session), défense dès qu'une révision est due et qu'aucun fait
nouveau n'est possible (ou dès 3 révisions dues), exploration si des faits
nouveaux sont autorisés, sinon arène.

## Journal brut

Chaque réponse est enregistrée : horodatage, session, jour, fait, orientation,
mode, options proposées, réponse donnée, juste/faux, rapide, suspecte, temps de
réponse, temps cible, révision due ou non, contexte de mission. Les débuts de
session sont aussi journalisés. `LearningEngine.rebuild_from_journal(entries)`
recalcule tous les états et la calibration à partir du journal seul, ce qui
permet de faire évoluer l'algorithme sans perdre l'historique.

## Validation

`tests/simulation/` fait jouer des élèves fictifs (courbe d'oubli
exponentielle, stabilité qui croît à chaque rappel réussi, confusions
persistantes, temps moteur propre à chaque élève). Les tests vérifient
qu'ils colonisent la galaxie en un nombre raisonnable de sessions, que les
faits déclarés maîtrisés sont réellement retenus à deux semaines, qu'une
absence de deux semaines ne provoque pas d'avalanche, et que le journal
rejoué redonne exactement l'état courant.
