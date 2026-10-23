import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/time/clinical_time.dart';
import '../domain/authorized_clinical_record.dart';
import 'fhir_record_providers.dart';

class AuthorizedClinicalRecordScreen extends ConsumerWidget {
  const AuthorizedClinicalRecordScreen({
    super.key,
    required this.hospitalizationId,
  });
  final String hospitalizationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(
      authorizedClinicalRecordProvider(hospitalizationId),
    );
    return Scaffold(
      appBar: clinicalBackAppBar(context, title: 'Ficha clínica electrónica'),
      body: record.when(
        skipLoadingOnRefresh: false,
        skipError: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _RetryState(
          message: 'No fue posible cargar la ficha clínica electrónica.',
          onRetry: () => ref.invalidate(
            authorizedClinicalRecordProvider(hospitalizationId),
          ),
        ),
        data: (value) => value == null
            ? const _NeutralState(
                'No se pudo verificar el acceso. Vuelve a cargar la pantalla.',
              )
            : _RecordBody(record: value),
      ),
    );
  }
}

class _RecordBody extends StatelessWidget {
  const _RecordBody({required this.record});
  final AuthorizedClinicalRecord record;

  static const labels = {
    'conditions': 'Condiciones',
    'observations': 'Observaciones',
    'medications': 'Medicamentos',
    'procedures': 'Procedimientos',
    'reports': 'Informes',
    'allergies': 'Alergias',
  };

  @override
  Widget build(BuildContext context) {
    final episode = record.hospitalization;
    final discharged = episode.status == 'discharged';
    return ListView(
      padding: const EdgeInsets.all(ClinicalSpacing.page),
      children: [
        ClinicalCard(
          padding: const EdgeInsets.all(ClinicalSpacing.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.patient.name,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: ClinicalSpacing.item),
              Wrap(
                spacing: ClinicalSpacing.compact,
                runSpacing: ClinicalSpacing.compact,
                children: [
                  if (record.patient.identifier != null)
                    _RecordMeta('Identificador', record.patient.identifier!),
                  if (record.patient.birthDate != null)
                    _RecordMeta(
                      'Nacimiento',
                      '${_displayDate(record.patient.birthDate!, true)}${_age(record.patient.birthDate!) == null ? '' : ' · ${_age(record.patient.birthDate!)} años'}',
                    ),
                  if (record.patient.gender != null)
                    _RecordMeta('Sexo', _genderLabel(record.patient.gender!)),
                ],
              ),
              const Divider(),
              Wrap(
                spacing: ClinicalSpacing.compact,
                runSpacing: ClinicalSpacing.compact,
                children: [
                  ClinicalBadge(
                    label: discharged
                        ? 'Cerrada'
                        : episode.status == 'temporarily_absent'
                        ? 'Ausente temporalmente'
                        : episode.status == 'planned'
                        ? 'Planificada'
                        : 'Abierta',
                    color: ClinicalColors.softMint,
                    textColor: ClinicalColors.mintBadgeText,
                    icon: Icons.local_hospital_outlined,
                  ),
                  _RecordMeta(
                    'Ubicación',
                    [episode.unit, episode.bed]
                            .whereType<String>()
                            .where((v) => v.isNotEmpty)
                            .join(' · ')
                            .isEmpty
                        ? 'Ubicación no registrada'
                        : [episode.unit, episode.bed]
                              .whereType<String>()
                              .where((v) => v.isNotEmpty)
                              .join(' · '),
                  ),
                  if (episode.dischargedAt != null)
                    _RecordMeta(
                      'Egreso',
                      formatClinicalDateTime(
                        DateTime.parse(episode.dischargedAt!),
                      ),
                    ),
                  if (discharged)
                    const ClinicalBadge(
                      label: 'Solo lectura',
                      color: ClinicalColors.softObservation,
                      textColor: ClinicalColors.observationText,
                    ),
                ],
              ),
            ],
          ),
        ),
        if (record.status == 'partial' || record.truncated)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: ClinicalSpacing.item),
            child: Text('La ficha puede estar incompleta.'),
          ),
        for (final section in record.sections)
          Padding(
            padding: const EdgeInsets.only(top: ClinicalSpacing.item),
            child: ClinicalCard(
              child: ExpansionTile(
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        labels[section.type] ?? section.type,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ClinicalBadge(
                      label: '${section.entries.length}',
                      color: _sectionColor(section.type).$1,
                      textColor: _sectionColor(section.type).$2,
                    ),
                  ],
                ),
                children: [
                  for (var i = 0; i < section.entries.length; i++) ...[
                    if (i > 0)
                      const Divider(
                        indent: ClinicalSpacing.card,
                        endIndent: ClinicalSpacing.card,
                      ),
                    _RecordEntryTile(entry: section.entries[i]),
                  ],
                ],
              ),
            ),
          ),
        if (record.sections.isEmpty)
          const Padding(
            padding: EdgeInsets.all(ClinicalSpacing.card),
            child: Text('No hay registros clínicos disponibles.'),
          ),
      ],
    );
  }
}

class _RecordMeta extends StatelessWidget {
  const _RecordMeta(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.labelMedium),
      Text(value, style: Theme.of(context).textTheme.bodyMedium),
    ],
  );
}

class _RecordEntryTile extends StatelessWidget {
  const _RecordEntryTile({required this.entry});
  final ClinicalRecordEntry entry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: ClinicalSpacing.card,
      vertical: ClinicalSpacing.item,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.title,
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        if (entry.detail?.isNotEmpty == true) ...[
          const SizedBox(height: ClinicalSpacing.compact),
          Text(entry.detail!, style: Theme.of(context).textTheme.bodyLarge),
        ],
        if (entry.date != null) ...[
          const SizedBox(height: ClinicalSpacing.compact),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: ClinicalSpacing.compact),
              Expanded(
                child: Text(
                  '${entry.isDateOnly ? 'Solo fecha · ' : ''}${_displayDate(entry.date!, entry.isDateOnly)}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}

String _genderLabel(String gender) => switch (gender) {
  'male' => 'Masculino',
  'female' => 'Femenino',
  'other' => 'Otro',
  'unknown' => 'No informado',
  _ => gender,
};

(Color, Color) _sectionColor(String type) => switch (type) {
  'conditions' => (ClinicalColors.softCondition, ClinicalColors.conditionText),
  'observations' => (
    ClinicalColors.softObservation,
    ClinicalColors.observationText,
  ),
  'medications' => (
    ClinicalColors.softMedication,
    ClinicalColors.medicationText,
  ),
  'procedures' => (ClinicalColors.softProcedure, ClinicalColors.procedureText),
  'reports' => (ClinicalColors.softReport, ClinicalColors.reportText),
  'allergies' => (ClinicalColors.softAttention, ClinicalColors.attention),
  _ => (ClinicalColors.canvas, ClinicalColors.secondary),
};

int? _age(String raw) {
  final parts = raw.split('-').map(int.tryParse).toList();
  if (parts.length != 3 || parts.any((part) => part == null)) return null;
  final birth = DateTime(parts[0]!, parts[1]!, parts[2]!);
  final now = DateTime.now();
  return now.year -
      birth.year -
      ((now.month < birth.month ||
              (now.month == birth.month && now.day < birth.day))
          ? 1
          : 0);
}

String _displayDate(String raw, bool dateOnly) => dateOnly
    ? raw.split('-').reversed.join('-')
    : formatClinicalDateTime(DateTime.parse(raw));

class _RetryState extends StatelessWidget {
  const _RetryState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(ClinicalSpacing.page),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: ClinicalSpacing.item),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}

class _NeutralState extends StatelessWidget {
  const _NeutralState(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(ClinicalSpacing.page),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}
