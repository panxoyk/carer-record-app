import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../data/fhir_record_repository_impl.dart';
import '../domain/fhir_record_entities.dart';

final fhirRecordRepositoryProvider = Provider<FhirRecordRepository>(
  (ref) => FhirRecordRepositoryImpl(),
);

final fhirPatientSearchProvider = FutureProvider.autoDispose
    .family<List<PatientSummary>, String>((ref, query) {
      return ref.watch(fhirRecordRepositoryProvider).searchPatients(query);
    });

final fhirClinicalRecordProvider = FutureProvider.autoDispose
    .family<ClinicalRecord, String>((ref, patientId) {
      return ref.watch(fhirRecordRepositoryProvider).loadRecord(patientId);
    });

String _fmt(DateTime? d) => d == null
    ? ''
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ---------------------------------------------------------------- Búsqueda

class FhirPatientSearchScreen extends ConsumerStatefulWidget {
  const FhirPatientSearchScreen({super.key});

  @override
  ConsumerState<FhirPatientSearchScreen> createState() =>
      _FhirPatientSearchScreenState();
}

class _FhirPatientSearchScreenState
    extends ConsumerState<FhirPatientSearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.length < 2
        ? null
        : ref.watch(fhirPatientSearchProvider(_query));

    return Scaffold(
      appBar: clinicalBackAppBar(context, title: 'Buscar paciente'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              onChanged: _onChanged,
              onSubmitted: (v) => setState(() => _query = v.trim()),
              textInputAction: TextInputAction.search,
              decoration: clinicalInputDecoration(
                labelText: 'Nombre, apellido o identificador',
              ),
            ),
          ),
          Expanded(
            child: results == null
                ? const Center(child: Text('Escribe al menos 2 caracteres.'))
                : results.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => _ErrorView(
                      message: '$e',
                      onRetry: () =>
                          ref.invalidate(fhirPatientSearchProvider(_query)),
                    ),
                    data: (patients) => patients.isEmpty
                        ? const Center(child: Text('Sin resultados.'))
                        : ListView.separated(
                            itemCount: patients.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final p = patients[i];
                              final age = p.age;
                              return ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(p.displayName),
                                subtitle: Text(
                                  [
                                    if (age != null) '$age años',
                                    if (p.genderLabel != null) p.genderLabel!,
                                    if (p.ward != null) p.ward!,
                                    if (p.bed != null) 'cama ${p.bed}',
                                  ].join(' · '),
                                ),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () =>
                                    context.push('/fhir/patients/${p.id}'),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Ficha

class FhirClinicalRecordScreen extends ConsumerWidget {
  const FhirClinicalRecordScreen({super.key, required this.patientId});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = ref.watch(fhirClinicalRecordProvider(patientId));

    return Scaffold(
      appBar: clinicalBackAppBar(context, title: 'Ficha clínica'),
      body: record.when(
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Solicitando ficha completa…'),
            ],
          ),
        ),
        error: (e, _) => _ErrorView(
          message: '$e',
          onRetry: () => ref.invalidate(fhirClinicalRecordProvider(patientId)),
        ),
        data: (r) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PatientHeader(patient: r.patient),
            if (r.truncated)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'La ficha es muy extensa y se muestra incompleta.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 8),
            for (final s in r.sections.entries)
              Card(
                child: ExpansionTile(
                  title: Text('${s.key} (${s.value.length})'),
                  children: [
                    for (final e in s.value)
                      ListTile(
                        dense: true,
                        title: Text(e.title),
                        subtitle: (e.detail == null || e.detail!.isEmpty)
                            ? null
                            : Text(e.detail!),
                        trailing: Text(_fmt(e.date)),
                      ),
                  ],
                ),
              ),
            if (r.sections.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('El paciente no tiene registros.')),
              ),
          ],
        ),
      ),
    );
  }
}

class _PatientHeader extends StatelessWidget {
  const _PatientHeader({required this.patient});
  final PatientSummary patient;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(patient.displayName, style: t.headlineSmall),
        const SizedBox(height: 4),
        Text(
          [
            if (patient.age != null) '${patient.age} años',
            if (patient.genderLabel != null) patient.genderLabel!,
            if (patient.birthDate != null) 'nac. ${_fmt(patient.birthDate)}',
          ].join(' · '),
        ),
        if (patient.ward != null || patient.bed != null)
          Text(
            [
              if (patient.ward != null) patient.ward!,
              if (patient.bed != null) 'cama ${patient.bed}',
              if (patient.admissionDate != null)
                'ingreso ${_fmt(patient.admissionDate)}',
            ].join(' · '),
          ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    ),
  );
}
