class_name EngineConfig
extends RefCounted
## Paramètres du moteur d'apprentissage (section 4 du document de conception).
##
## Tous les seuils « à valider en test réel » (10.3) sont regroupés ici pour
## pouvoir être ajustés sans toucher à la logique.

## Tables couvertes (question ouverte 10.3 : ×0 et ×11/×12 restent configurables).
var table_min: int = 1
var table_max: int = 10
var include_zero: bool = false

## Ordre de découverte des tables (5.2) : système d'origine, ceinture, confins.
var table_order: Array = [1, 10, 2, 5, 3, 4, 9, 6, 7, 8]

## Boîtes de Leitner, de 0 (jamais vu) à 5.
var box_max: int = 5
## Intervalles de révision (4.6) : une révision est due quand les DEUX minimums
## sont atteints. Index = numéro de boîte.
var min_sessions_per_box: Array = [0, 0, 1, 2, 3, 4]
var min_days_per_box: Array = [0, 0, 1, 3, 7, 21]
## Un fait qui rechute souvent reçoit des intervalles plus prudents :
## jours minimum × facteur^rechutes (jamais en dessous de 1 jour à partir de la boîte 2).
var relapse_interval_factor: float = 0.75

## Composition d'une session (4.7).
var max_reviews_per_session: int = 10
var max_new_facts_per_session: int = 3
var min_new_facts_per_session: int = 2
var new_facts_error_rate_limit: float = 0.20
var new_facts_pending_reviews_limit: int = 8
var error_rate_window: int = 20
var items_per_session: int = 20
var warmup_trivial_facts: int = 2
var max_asks_per_fact_per_session: int = 3
var reinsert_after_min: int = 2
var reinsert_after_max: int = 3
var frustration_consecutive_errors: int = 2

## Seuil de rapidité (4.4) : temps moteur de base (mesuré sur les faits
## triviaux) + marge. Valeurs par défaut avant calibration.
var speed_margin_ms: int = 2000
var default_motor_base_ms: Dictionary = {"qcm": 1200, "wheel": 2500, "decomposition": 3000}
var calibration_window: int = 10
var calibration_min_samples: int = 3

## Anti-hasard (4.5) : une réponse QCM plus rapide que ce seuil ne fait pas progresser.
var anti_random_ms: int = 400

## Règles de passage (4.5).
var qcm_successes_for_consolidation: int = 3
var qcm_sessions_for_consolidation: int = 2
var mastery_box: int = 4
## Réponses rapides à la roue nécessaires, une fois la boîte de maîtrise atteinte.
var wheel_fast_successes_for_mastery: int = 1

## Historique récent conservé par fait (4.2).
var history_size: int = 5

## Orientation (4.1) : probabilité de présenter l'orientation la plus faible
## quand les statistiques des deux orientations divergent.
var weak_orientation_bias: float = 0.7
var orientation_divergence_ms: int = 800
var orientation_divergence_rate: float = 0.15
