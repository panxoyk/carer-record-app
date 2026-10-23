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
              if (record.patient.identifier != null)
                Text('Identificador: ${record.patient.identifier}'),
              if (record.patient.birthDate != null)
                Text(
                  'Nacimiento: ${_displayDate(record.patient.birthDate!, true)}${_age(record.patient.birthDate!) == null ? '' : ' · ${_age(record.patient.birthDate!)} años'}',
                ),
              if (record.patient.gender != null)
                Text('Sexo: ${record.patient.gender}'),
              const Divider(),
              Text(
                'Hospitalización: ${discharged
                    ? 'Cerrada'
                    : episode.status == 'temporarily_absent'
                    ? 'Ausente temporalmente'
                    : episode.status == 'planned'
                    ? 'Planificada'
                    : 'Abierta'}',
              ),
              Text(
                'Ubicación: ${[episode.unit, episode.bed].whereType<String>().where((v) => v.isNotEmpty).join(' · ').isEmpty ? 'Ubicación no registrada' : [episode.unit, episode.bed].whereType<String>().where((v) => v.isNotEmpty).join(' · ')}',
              ),
              if (episode.dischargedAt != null)
                Text(
                  'Egreso: ${formatClinicalDateTime(DateTime.parse(episode.dischargedAt!))}',
                ),
              if (discharged) const Text('Solo lectura'),
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
                title: Text(
                  '${labels[section.type] ?? section.type} (${section.entries.length})',
                ),
                children: [
                  for (final entry in section.entries)
                    ListTile(
                      title: Text(entry.title),
                      subtitle: Text(
                        [
                          if (entry.detail?.isNotEmpty == true) entry.detail!,
                          if (entry.date != null)
                            '${entry.isDateOnly ? 'Solo fecha' : ''}${entry.isDateOnly ? ' · ' : ''}${_displayDate(entry.date!, entry.isDateOnly)}',
                        ].join(' · '),
                      ),
                    ),
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
