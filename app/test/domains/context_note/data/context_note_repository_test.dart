import 'package:carer_record_app/domains/context_note/data/context_note_repository.dart';
import 'package:carer_record_app/domains/context_note/domain/entities/context_note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const milestone = ContextNoteMilestone(
    organizationId: 'org',
    hospitalizationId: 'episode',
    patientId: 'patient',
    inputMethod: MilestoneInputMethod.text,
    content: '  confirmed note  ',
    clientEventId: 'stable-id',
  );

  test('reconciles a committed insert whose response was lost', () async {
    final remote = _Remote()
      ..failInsert = true
      ..matches = true;
    final repository = ContextNoteRepository.withRemote(remote);

    await repository.saveMilestone(milestone);

    expect(remote.inserted, hasLength(1));
    expect(remote.inserted.single['client_event_id'], 'stable-id');
    expect(remote.inserted.single['content'], 'confirmed note');
    expect(remote.checked, remote.inserted.single);
  });

  test('does not accept a key collision with a mismatched payload', () async {
    final remote = _Remote()..failInsert = true;
    final repository = ContextNoteRepository.withRemote(remote);
    final failure = StateError('unique collision');
    remote.insertFailure = failure;

    await expectLater(
      repository.saveMilestone(milestone),
      throwsA(same(failure)),
    );
    expect(remote.matchesCalled, isTrue);
  });

  test('preserves original error when reconciliation fails', () async {
    final remote = _Remote()
      ..failInsert = true
      ..insertFailure = StateError('insert failed')
      ..failReconciliation = true;
    final repository = ContextNoteRepository.withRemote(remote);
    final failure = remote.insertFailure;
    await expectLater(
      repository.saveMilestone(milestone),
      throwsA(same(failure)),
    );
  });
}

class _Remote implements ContextNoteRemote {
  bool failInsert = false;
  bool matches = false;
  Object insertFailure = StateError('response lost');
  Map<String, Object?>? checked;
  bool matchesCalled = false;
  bool failReconciliation = false;
  final inserted = <Map<String, Object?>>[];

  @override
  Future<void> insert(Map<String, Object?> payload) async {
    inserted.add(payload);
    if (failInsert) throw insertFailure;
  }

  @override
  Future<bool> publicationMatches(Map<String, Object?> payload) async {
    matchesCalled = true;
    checked = payload;
    if (failReconciliation) throw StateError('reconciliation failed');
    return matches;
  }
}
