import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design_system/clinical_design_system.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../clinical_event/domain/entities/clinical_event.dart';
import '../../clinical_event/presentation/clinical_event_providers.dart';
import '../domain/entities/patient.dart';
import 'patient_providers.dart';

const _mint = ClinicalColors.mint;
const _mintDark = ClinicalColors.mintDark;
const _softMint = ClinicalColors.softMint;
const _ink = ClinicalColors.ink;
const _canvas = ClinicalColors.canvas;
const _secondary = ClinicalColors.secondary;
const _tertiary = ClinicalColors.tertiary;
const _separator = ClinicalColors.separator;

class PatientsScreen extends ConsumerStatefulWidget {
  const PatientsScreen({super.key});

  @override
  ConsumerState<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends ConsumerState<PatientsScreen> {
  String _query = '';
  String _activeUnit = 'Todos';

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(patientsProvider(_query));
    return Scaffold(
      backgroundColor: _canvas,
      bottomNavigationBar: const ClinicalBottomNavigation(selectedIndex: 0),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 2),
              child: Text(
                'Casos activos',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  letterSpacing: -1,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Text(
                'Pacientes hospitalizados bajo tu atención',
                style: TextStyle(fontSize: 15, color: _secondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: 'Buscar paciente...',
                  hintStyle: const TextStyle(color: _tertiary),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: const Color(0xffe9e9ee),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            Expanded(
              child: patients.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error:
                    (_, __) => const Center(
                      child: Text('No fue posible cargar los pacientes.'),
                    ),
                data: (items) {
                  final units = <String>{
                    'Todos',
                    ...items
                        .map((patient) => patient.careUnit)
                        .whereType<String>(),
                  };
                  final visible =
                      _activeUnit == 'Todos'
                          ? items
                          : items
                              .where(
                                (patient) => patient.careUnit == _activeUnit,
                              )
                              .toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 54,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                          itemCount: units.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, index) {
                            final unit = units.elementAt(index);
                            final selected = unit == _activeUnit;
                            return ChoiceChip(
                              label: Text(unit),
                              selected: selected,
                              onSelected:
                                  (_) => setState(() => _activeUnit = unit),
                              showCheckmark: false,
                              labelStyle: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: selected ? Colors.white : _secondary,
                              ),
                              selectedColor: _ink,
                              backgroundColor: const Color(0x1f767680),
                              side: BorderSide.none,
                              shape: const StadiumBorder(),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
                        child: Text(
                          '${visible.length} ${visible.length == 1 ? 'CASO' : 'CASOS'}',
                          style: const TextStyle(
                            fontSize: 12,
                            letterSpacing: .7,
                            fontWeight: FontWeight.w700,
                            color: _secondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child:
                            visible.isEmpty
                                ? const Center(
                                  child: Text('No se encontraron pacientes.'),
                                )
                                : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    0,
                                    16,
                                    24,
                                  ),
                                  itemCount: visible.length,
                                  separatorBuilder:
                                      (_, __) => const SizedBox(height: 12),
                                  itemBuilder:
                                      (_, index) =>
                                          _PatientCard(patient: visible[index]),
                                ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PatientCard extends StatelessWidget {
  const _PatientCard({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.go('/patients/${patient.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: _softMint,
                  foregroundColor: const Color(0xff1aae90),
                  child: Text(
                    _initials(patient.fullName),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    patient.fullName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: _tertiary),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: _separator),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.bed_outlined, size: 17, color: _secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    patient.locationLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _secondary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.circle, size: 8, color: _mint),
                const SizedBox(width: 6),
                const Text(
                  'Ficha activa',
                  style: TextStyle(fontSize: 12, color: _secondary),
                ),
                const Spacer(),
                Text(
                  'RUT: ${patient.rut ?? 'No registrado'}',
                  style: const TextStyle(fontSize: 12, color: _secondary),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class PatientDetailScreen extends ConsumerStatefulWidget {
  const PatientDetailScreen({required this.patientId, super.key});

  final String patientId;

  @override
  ConsumerState<PatientDetailScreen> createState() =>
      _PatientDetailScreenState();
}

class _PatientDetailScreenState extends ConsumerState<PatientDetailScreen> {
  String _activeFilter = 'Todos';

  @override
  Widget build(BuildContext context) {
    final patient = ref.watch(patientProvider(widget.patientId));
    return Scaffold(
      backgroundColor: _canvas,
      appBar: clinicalBackAppBar(context, title: ''),
      bottomNavigationBar: const ClinicalBottomNavigation(selectedIndex: 0),
      body: patient.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) => const Center(
              child: Text('No fue posible cargar la ficha del paciente.'),
            ),
        data:
            (item) =>
                item == null
                    ? const Center(child: Text('Paciente no encontrado.'))
                    : _PatientTimeline(
                      patient: item,
                      activeFilter: _activeFilter,
                      onFilterChanged:
                          (value) => setState(() => _activeFilter = value),
                    ),
      ),
    );
  }
}

class _PatientTimeline extends ConsumerWidget {
  const _PatientTimeline({
    required this.patient,
    required this.activeFilter,
    required this.onFilterChanged,
  });

  final Patient patient;
  final String activeFilter;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(patientClinicalEventsProvider(patient.id));
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text(
              'Bitácora',
              style: const TextStyle(
                fontSize: 28,
                letterSpacing: -.6,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => context.go('/patients/${patient.id}/details'),
              child: Container(
                decoration: BoxDecoration(
                  color: _softMint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0x404eddb3)),
                ),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: _mint,
                      foregroundColor: _ink,
                      child: Text(
                        _initials(patient.fullName),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient.fullName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _mintDark,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${patient.locationLabel} · RUT ${patient.rut ?? 'sin registro'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: _mintDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: _mintDark),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Icon(Icons.circle, size: 7, color: _mint),
                SizedBox(width: 7),
                Text(
                  'HOY · REGISTRO CLÍNICO',
                  style: TextStyle(fontSize: 12, color: _secondary),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: SizedBox(
            height: 45,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
              itemCount: _timelineFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final filter = _timelineFilters[index];
                final selected = filter == activeFilter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: (_) => onFilterChanged(filter),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: selected ? Colors.white : _secondary,
                  ),
                  selectedColor: _ink,
                  backgroundColor: const Color(0x1f767680),
                  side: BorderSide.none,
                  shape: const StadiumBorder(),
                );
              },
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Text(
              'Eventos recientes',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
        ),
        events.when(
          loading:
              () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
          error:
              (_, __) => const SliverFillRemaining(
                child: Center(
                  child: Text('No fue posible cargar los eventos.'),
                ),
              ),
          data: (items) {
            final visible =
                activeFilter == 'Todos'
                    ? items
                    : items
                        .where(
                          (event) => _eventFilter(event.kind) == activeFilter,
                        )
                        .toList();
            if (visible.isEmpty) {
              return const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('No hay eventos en esta categoría.')),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: visible.length,
                itemBuilder:
                    (_, index) => _TimelineEvent(
                      event: visible[index],
                      isLast: index == visible.length - 1,
                    ),
                separatorBuilder: (_, __) => const SizedBox(height: 2),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({required this.event, required this.isLast});

  final ClinicalEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _eventStyle(event.kind).color,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
              if (!isLast)
                Expanded(child: Container(width: 1, color: _separator)),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(15, 13, 15, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _formatDateTime(event.occurredAt),
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _tertiary,
                          ),
                        ),
                        const Spacer(),
                        _EventKindPill(style: _eventStyle(event.kind)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _eventKindLabel(event.kind),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      event.summary,
                      style: const TextStyle(fontSize: 13, color: _secondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

const _timelineFilters = [
  'Todos',
  'Clínica',
  'Procedimientos',
  'Observaciones',
];

String _eventFilter(String kind) => switch (kind) {
  'procedure' => 'Procedimientos',
  'observation' => 'Observaciones',
  _ => 'Clínica',
};

class _EventStyle {
  const _EventStyle(this.label, this.color, this.background);
  final String label;
  final Color color;
  final Color background;
}

_EventStyle _eventStyle(String kind) => switch (kind) {
  'observation' => const _EventStyle(
    'Observación',
    _secondary,
    Color(0x1f6e6e73),
  ),
  'procedure' => const _EventStyle(
    'Procedimiento',
    Color(0xffff3b30),
    Color(0x1fff3b30),
  ),
  'document' => const _EventStyle(
    'Documento',
    Color(0xff007aff),
    Color(0x1f007aff),
  ),
  'condition' => const _EventStyle(
    'Condición',
    Color(0xffff9500),
    Color(0x1fff9500),
  ),
  _ => const _EventStyle('Nota clínica', Color(0xff007aff), Color(0x1f007aff)),
};

class _EventKindPill extends StatelessWidget {
  const _EventKindPill({required this.style});
  final _EventStyle style;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: style.background,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      style.label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: style.color,
      ),
    ),
  );
}

class PatientInformationScreen extends ConsumerWidget {
  const PatientInformationScreen({required this.patientId, super.key});

  final String patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = ref.watch(patientProvider(patientId));
    return Scaffold(
      backgroundColor: _canvas,
      appBar: clinicalBackAppBar(context, title: 'Información del paciente'),
      bottomNavigationBar: const ClinicalBottomNavigation(selectedIndex: 0),
      body: patient.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:
            (_, __) => const Center(
              child: Text('No fue posible cargar la información.'),
            ),
        data:
            (item) =>
                item == null
                    ? const Center(child: Text('Paciente no encontrado.'))
                    : _PatientInformation(patient: item),
      ),
    );
  }
}

class _PatientInformation extends StatelessWidget {
  const _PatientInformation({required this.patient});

  final Patient patient;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
    children: [
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: _softMint,
                    foregroundColor: _mintDark,
                    child: Text(
                      _initials(patient.fullName),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.fullName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          patient.birthDate == null
                              ? 'Ficha clínica'
                              : 'Nacimiento: ${_formatDate(patient.birthDate)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _softMint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Activo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _mintDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _separator),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                children: [
                  _PatientInfoRow(
                    icon: Icons.bed_outlined,
                    label: 'Ubicación',
                    value: patient.locationLabel,
                  ),
                  _PatientInfoRow(
                    icon: Icons.badge_outlined,
                    label: 'Referencia externa',
                    value: patient.externalReference ?? 'No registrada',
                  ),
                  _PatientInfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Nacimiento',
                    value: _formatDate(patient.birthDate),
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: _separator,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DetailRow('RUT', patient.rut ?? 'No registrado'),
                  _DetailRow('Unidad', patient.careUnit ?? 'No registrada'),
                  _DetailRow(
                    'Cama',
                    patient.bedLabel ?? 'No registrada',
                    isLast: true,
                  ),
                ],
              ),
            ),
            const Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: _separator,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: _mint),
                  const SizedBox(width: 7),
                  const Text(
                    'Hospitalización activa',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          'NAVEGACIÓN',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: .7,
            fontWeight: FontWeight.w700,
            color: _secondary,
          ),
        ),
      ),
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.go('/patients/${patient.id}'),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            child: Row(
              children: [
                Icon(Icons.article_outlined, color: _secondary),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bitácora',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Historial de eventos clínicos',
                        style: TextStyle(fontSize: 12, color: _secondary),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: _tertiary),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _PatientInfoRow extends StatelessWidget {
  const _PatientInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, size: 17, color: _secondary),
        const SizedBox(width: 10),
        SizedBox(
          width: 108,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: _secondary),
          ),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _ink,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value, {this.isLast = false});

  final String label;
  final String value;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: isLast ? 0 : 18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xff71717a)),
        ),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: _ink)),
      ],
    ),
  );
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final practitioner = ref.watch(currentPractitionerProvider);
    final session = ref.watch(sessionProvider);
    return Scaffold(
      backgroundColor: _canvas,
      bottomNavigationBar: const ClinicalBottomNavigation(selectedIndex: 1),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 28),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 18),
              child: Text(
                'Ajustes',
                style: TextStyle(
                  fontSize: 34,
                  letterSpacing: -1,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
            ),
            practitioner.when(
              loading:
                  () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  ),
              error: (_, __) => const _SettingsError(),
              data: (profile) {
                if (profile == null) return const _SettingsError();
                final email = session?.user.email;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClinicalProfileCard(
                      initials: _initials(profile.displayName),
                      name: profile.displayName,
                      subtitle: _roleLabel(profile.role),
                      status: profile.isActive ? 'Activo' : 'Suspendido',
                    ),
                    const SizedBox(height: 22),
                    ClinicalSettingsSection(
                      title: 'Perfil institucional',
                      children: [
                        ClinicalSettingsRow(
                          label: 'Nombre',
                          value: profile.displayName,
                          icon: Icons.person_outline_rounded,
                        ),
                        ClinicalSettingsRow(
                          label: 'Rol',
                          value: _roleLabel(profile.role),
                          icon: Icons.badge_outlined,
                        ),
                        ClinicalSettingsRow(
                          label: 'Estado',
                          value: profile.isActive ? 'Activo' : 'Suspendido',
                          icon: Icons.verified_outlined,
                          isLast: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    ClinicalSettingsSection(
                      title: 'Seguridad',
                      children: [
                        ClinicalSettingsRow(
                          label: 'Correo institucional',
                          value: email ?? 'No disponible',
                          icon: Icons.mail_outline_rounded,
                        ),
                        const ClinicalSettingsRow(
                          label: 'Sesión activa',
                          value: 'Activa',
                          icon: Icons.schedule_outlined,
                          isLast: true,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 22),
            ClinicalCard(
              child: ClinicalSettingsRow(
                label: 'Cerrar sesión',
                icon: Icons.logout_rounded,
                destructive: true,
                isLast: true,
                onTap: () => ref.read(authRepositoryProvider).signOut(),
              ),
            ),
            const SizedBox(height: 22),
            const Center(
              child: Column(
                children: [
                  Text(
                    'Carer Record',
                    style: TextStyle(fontSize: 12, color: _tertiary),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Uso exclusivo de personal clínico autorizado',
                    style: TextStyle(fontSize: 11, color: _tertiary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(20),
    child: Text('No fue posible cargar el perfil.'),
  );
}

String _initials(String fullName) =>
    fullName
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join();

String _formatDate(DateTime? value) {
  if (value == null) return 'No registrada';
  return '${value.day.toString().padLeft(2, '0')}-${value.month.toString().padLeft(2, '0')}-${value.year}';
}

String _formatDateTime(DateTime value) =>
    '${_formatDate(value)} · ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _eventKindLabel(String kind) => switch (kind) {
  'observation' => 'Observación',
  'encounter' => 'Encuentro',
  'condition' => 'Condición',
  'procedure' => 'Procedimiento',
  'document' => 'Documento',
  _ => kind,
};

String _roleLabel(String role) => switch (role) {
  'physician' => 'Médico/a',
  'nurse' => 'Enfermero/a',
  'technician' => 'Técnico/a',
  'administrator' => 'Administrador/a',
  _ => role,
};
