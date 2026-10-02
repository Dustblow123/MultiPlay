extends SceneTree
## Outil de réglage de l'algorithme : joue une simulation et affiche, toutes
## les 5 sessions, les états, rechutes, erreurs par état et faits nouveaux,
## puis le détail des faits non maîtrisés à la fin.
##
##   godot --headless --path . -s tests/simulation/diagnose.gd -- [sessions] [ability] [seed]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var sessions: int = int(args[0]) if args.size() > 0 else 70
	var ability: float = float(args[1]) if args.size() > 1 else 1.0
	var seed: int = int(args[2]) if args.size() > 2 else 100
	var engine := LearningEngine.new(null, seed)
	var student := SimulatedStudent.new(seed, ability)
	var mission := {}
	for s in range(sessions):
		var summary := engine.start_session(s)
		var err_by_state := {"new": 0, "learning": 0, "consolidation": 0, "mastered": 0}
		var ask_by_state := {"new": 0, "learning": 0, "consolidation": 0, "mastered": 0}
		var err_due := 0
		var err_practice := 0
		for m in range(2):
			mission = engine.suggest_mission()
			var ctx := {"type": mission["type"]}
			if mission.has("pair"):
				ctx["pair"] = mission["pair"]
			for i in range(20):
				var item := engine.next_item(ctx)
				var resp := student.answer(item, s)
				var out := engine.report_result(item, resp["given"], resp["time_ms"])
				ask_by_state[item["state"]] += 1
				if not out["correct"]:
					err_by_state[item["state"]] += 1
					if item["is_due"]:
						err_due += 1
					else:
						err_practice += 1
		var stats := engine.end_session()
		if s % 5 == 0 or s == sessions - 1:
			print("s%02d %-11s due=%2d new=%d | %s | rechutes=%d err due=%d practice=%d | err/état %s asks %s | taux err %.2f" % [
				s + 1, mission["type"], summary["due"], summary["planned_new"].size(), str(engine.counts_by_state()),
				stats["relapsed"].size(), err_due, err_practice, str(err_by_state), str(ask_by_state), engine.recent_error_rate()])
	print("--- jour %d, session %d" % [engine.current_day, engine.session_id])
	for fs in engine.states.values():
		if fs.state != FactState.State.MASTERED:
			var h := []
			for e in fs.history:
				h.append("%s%s@s%d" % ["+" if e["correct"] else "-", "f" if e["fast"] else "", e["session"]])
			print("%s box=%d due s%d/j%d relapses=%d wstreak=%d hist=%s" % [fs.key, fs.box, fs.due_session, fs.due_day, fs.relapses, fs.wheel_fast_streak, " ".join(h)])
	quit(0)
