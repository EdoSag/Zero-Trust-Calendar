import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zero_trust_core/zero_trust_core.dart';

/// The plan feature that opens the automatic Planner (Plus). "Find a time
/// for a task" stays free.
const plannerFeature = 'planner';

/// Whether [plan] includes the Planner. Null when the plan isn't known
/// (locked, signed out, offline, still loading): nothing is held back then,
/// so a Plus account without a connection keeps its Planner.
///
/// The hidden Unlimited plan lists `*`, every feature.
bool? plannerAllowedFor(ZtPlan? plan) =>
    plan == null ? null : plan.features.contains('*') || plan.has(plannerFeature);

/// Whether this account may use the automatic Planner: true, false, or
/// null while that isn't known. Only a definite false pauses it. The
/// check is on the phone only (the Planner never talks to a server).
final plannerAllowedProvider = Provider.autoDispose<bool?>(
  (ref) => plannerAllowedFor(ref.watch(ztPlanProvider).value),
);
