import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../data/fhir_record_repository_impl.dart';
import '../domain/fhir_record_entities.dart';
import '../domain/hospitalization_link.dart';

final fhirRecordRepositoryProvider = Provider<FhirRecordRepository>(
  (ref) => FhirRecordRepositoryImpl(),
);

final fhirClinicalRecordProvider = FutureProvider.autoDispose
    .family<ClinicalRecord, String>((ref, patientId) {
      return ref.watch(fhirRecordRepositoryProvider).loadRecord(patientId);
    });

String _fmt(DateTime? d) => d == null
    ? ''
    : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ----------------------------------------------------------------- Listado

/// Pantalla principal de pacientes: lista a todos los pacientes de HAPI FHIR
/// (paginado al hacer scroll) y filtra por nombre o identificador en el
/// servidor.
class FhirPatientListScreen extends ConsumerStatefulWidget {
  const FhirPatientListScreen({super.key});

  @override
  ConsumerState<FhirPatientListScreen> createState() =>
      _FhirPatientListScreenState();
}

class _FhirPatientListScreenState extends ConsumerState<FhirPatientListScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _patients = <PatientSummary>[];
  Timer? _debounce;
  String _query = '';
  String? _nextPage;
  bool _loading = false;
  Object? _error;

  /// Descarta las respuestas de una carga anterior si el texto cambió.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      _load(reset: false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final query = value.trim();
      if (!mounted || query == _query) return;
      _query = query;
      _load(reset: true);
    });
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || _nextPage == null)) return;
    if (reset) _generation++;
    final generation = _generation;
    final pageToken = reset ? null : _nextPage;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _patients.clear();
        _nextPage = null;
      }
    });
    try {
      final page = await ref
          .read(fhirRecordRepositoryProvider)
          .listPatients(query: _query, pageToken: pageToken);
      if (!mounted || generation != _generation) return;
      setState(() {
        _patients.addAll(page.patients);
        _nextPage = page.nextPageToken;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      bottomNavigationBar: const ClinicalBottomNavigation(selectedIndex: 0),
      appBar: clinicalAppBar(title: 'Pacientes'),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: clinicalInputDecoration(
                labelText: 'Buscar por nombre o identificador',
              ),
            ),
          ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    // UI guard only: RLS sigue siendo la autoridad de autorización.
    final canReadTimeline =
        ref
            .watch(iamContextProvider)
            .valueOrNull
            ?.allows('clinical.timeline.read') ??
        false;
    if (_patients.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_patients.isEmpty && _error != null) {
      return _ErrorView(message: '$_error', onRetry: () => _load(reset: true));
    }
    return RefreshIndicator(
      onRefresh: () => _load(reset: true),
      child: _patients.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(
                  height: 160,
                  child: Center(child: Text('No se encontraron pacientes.')),
                ),
              ],
            )
          : ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: _patients.length + 1,
              itemBuilder: (context, index) => index == _patients.length
                  ? _footer()
                  : _PatientTile(
                      patient: _patients[index],
                      canReadTimeline: canReadTimeline,
                    ),
            ),
    );
  }

  /// Indicador al final de la lista mientras se carga la página siguiente, o
  /// el error con su reintento si esa carga falló.
  Widget _footer() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text('$_error', textAlign: TextAlign.center),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => _load(reset: false),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    return const SizedBox(height: 16);
  }
}

/// Cada paciente de FHIR abre la bitácora de su hospitalización en Supabase
/// (la que sincroniza scripts/fhir-sync). La ficha completa de FHIR sigue
/// disponible en `/fhir/patients/:patientId`.
class _PatientTile extends StatelessWidget {
  const _PatientTile({required this.patient, required this.canReadTimeline});

  final PatientSummary patient;
  final bool canReadTimeline;

  @override
  Widget build(BuildContext context) {
    final age = patient.age;
    final details = [
      if (age != null) '$age años',
      if (patient.genderLabel != null) patient.genderLabel!,
      if (patient.ward != null) patient.ward!,
      if (patient.bed != null) 'cama ${patient.bed}',
    ];
    return ListTile(
      title: Text(patient.displayName),
      subtitle: details.isEmpty ? null : Text(details.join(' · ')),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        final hospitalizationId = hospitalizationIdForFhirPatient(patient.id);
        if (hospitalizationId == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Este paciente no se puede enlazar con la bitácora.',
              ),
            ),
          );
          return;
        }
        // push (no go): la bitácora queda sobre el listado, así al volver se
        // conserva lo escrito en el buscador, el scroll y las páginas cargadas.
        context.push(
          canReadTimeline
              ? '/hospitalizations/$hospitalizationId'
              : '/hospitalizations/$hospitalizationId/details',
        );
      },
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
              Text(
                'Solicitando ficha completa…\nPuede tardar hasta un minuto.',
                textAlign: TextAlign.center,
              ),
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
