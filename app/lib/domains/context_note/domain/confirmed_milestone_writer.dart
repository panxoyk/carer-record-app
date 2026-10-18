import 'entities/context_note.dart';

/// Boundary for publishing an author-confirmed milestone.
abstract interface class ConfirmedMilestoneWriter {
  Future<void> saveMilestone(ContextNoteMilestone milestone);
}
