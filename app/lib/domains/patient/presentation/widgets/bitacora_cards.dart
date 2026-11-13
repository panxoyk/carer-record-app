import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/clinical/clinical_vocabulary.dart';
import '../../../../core/design_system/clinical_design_system.dart';
import '../../../../core/time/clinical_time.dart';
import '../../../fhir_record/domain/authorized_clinical_record.dart';
import '../../../fhir_record/presentation/fhir_record_providers.dart';

/// LOINC codes of nursing controls shown apart from the vital signs line.
const hgtCode = '41653-7';
const diuresisCode = '9187-6';
const _fluidIntake = 'fluid-intake';
const _fluidOutput = 'fluid-output';

DateTime? _instant(ClinicalRecordEntry entry) =>
    entry.date == null || entry.isDateOnly ? null : DateTime.parse(entry.date!);

String _timeOf(ClinicalRecordEntry entry) {
  final time = _instant(entry);
  return time == null
      ? (entry.date ?? 'Sin fecha')
      : formatClinicalDateTime(time);
}

/// Compact label of a vital sign, e.g. `FC 104 /min`.
String vitalLabel(ClinicalRecordEntry entry) {
  final short = switch (entry.code) {
    '8867-4' => 'FC',
    '9279-1' => 'FR',
    '8310-5' => 'Temp.',
    '2708-6' => 'SpO₂',
    '85354-9' => 'PA',
    _ => entry.title,
  };
  final value = (entry.value ?? '')
      .replaceAll('mm[Hg]', 'mmHg')
      .replaceAll(' Cel', ' °C');
  return '$short $value'.trim();
}

List<ClinicalRecordEntry> vitalSigns(AuthorizedClinicalRecord record) => record
    .entriesOf(ClinicalSectionType.observations)
    .where(
      (entry) =>
          entry.category == 'vital-signs' &&
          entry.code != hgtCode &&
          entry.code != diuresisCode &&
          _instant(entry) != null,
    )
    .toList();

/// Vital signs grouped by measurement instant, newest first.
List<({DateTime time, List<ClinicalRecordEntry> entries})> vitalsByTime(
  AuthorizedClinicalRecord record,
) {
  final groups = <DateTime, List<ClinicalRecordEntry>>{};
  for (final entry in vitalSigns(record)) {
    (groups[_instant(entry)!] ??= []).add(entry);
  }
  final ordered = groups.entries.toList()
    ..sort((a, b) => b.key.compareTo(a.key));
  return [for (final group in ordered) (time: group.key, entries: group.value)];
}

ClinicalRecordEntry? _latest(Iterable<ClinicalRecordEntry> entries) {
  ClinicalRecordEntry? best;
  for (final entry in entries) {
    final time = _instant(entry);
    if (time == null) continue;
    if (best == null || time.isAfter(_instant(best)!)) best = entry;
  }
  return best;
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    child: ClinicalCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: ClinicalTextStyles.headline),
          ),
          ...children,
        ],
      ),
    ),
  );
}

/// "Ver por hora" / "Ver resultados" expandable row in a card.
class _Expandable extends StatefulWidget {
  const _Expandable({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  State<_Expandable> createState() => _ExpandableState();
}

class _ExpandableState extends State<_Expandable> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 36),
          ),
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(
            _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 20,
          ),
          label: Text(widget.label),
        ),
      ),
      if (_open) widget.child,
    ],
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.lines, this.alert = false});
  final List<String> lines;
  final bool alert;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: alert ? const Color(0xffffebea) : ClinicalColors.canvas,
      borderRadius: BorderRadius.circular(ClinicalRadii.control),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines.length; i++)
          Text(
            lines[i],
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
              color: alert ? const Color(0xff8e1a12) : ClinicalColors.ink,
            ),
          ),
      ],
    ),
  );
}

/// Signos vitales: último control, detalle por hora, HGT y diuresis.
class VitalSignsCard extends StatelessWidget {
  const VitalSignsCard({required this.record, super.key});
  final AuthorizedClinicalRecord record;

  @override
  Widget build(BuildContext context) {
    final groups = vitalsByTime(record);
    final observations = record.entriesOf(ClinicalSectionType.observations);
    final hgt = _latest(observations.where((e) => e.code == hgtCode));
    final diuresis = _latest(observations.where((e) => e.code == diuresisCode));
    final latest = groups.isEmpty ? null : groups.first;
    final alert = latest?.entries.any((e) => e.isAbnormal) ?? false;
    return _SectionCard(
      title: 'Signos vitales',
      children: [
        if (latest == null)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Sin mediciones registradas.',
              style: ClinicalTextStyles.subhead,
            ),
          )
        else ...[
          const SizedBox(height: 2),
          Text(
            'Último control con valores · ${formatClinicalDateTime(latest.time)}',
            style: ClinicalTextStyles.footnote,
          ),
          const SizedBox(height: 4),
          Text(
            latest.entries.map(vitalLabel).join(' · '),
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: alert ? ClinicalColors.destructive : ClinicalColors.ink,
            ),
          ),
          _Expandable(
            label: 'Ver por hora',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final group in groups)
                  _Tile(
                    alert: group.entries.any((e) => e.isAbnormal),
                    lines: [
                      '${formatClinicalDateTime(group.time)} · ${group.entries.map(vitalLabel).join(' · ')}',
                      for (final entry in group.entries.where(
                        (e) => e.isAbnormal,
                      ))
                        '${entry.title}: ${entry.flag!.label.toLowerCase()}',
                    ],
                  ),
              ],
            ),
          ),
        ],
        const Divider(height: 16),
        _ControlRow(
          label: 'HGT · Glucemia capilar',
          value: hgt == null
              ? 'Sin medición registrada.'
              : '${hgt.value ?? ''} · ${_timeOf(hgt)}',
          alert: hgt?.isAbnormal ?? false,
        ),
        const SizedBox(height: 8),
        _ControlRow(
          label: 'Diuresis',
          value: diuresis == null
              ? 'Sin medición registrada.'
              : '${diuresis.value ?? ''} · ${_timeOf(diuresis)}',
        ),
      ],
    );
  }
}

class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.label,
    required this.value,
    this.alert = false,
  });
  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          color: alert ? ClinicalColors.destructive : ClinicalColors.secondary,
        ),
      ),
    ],
  );
}

/// Exámenes de sangre agrupados por toma.
class BloodResultsCard extends StatelessWidget {
  const BloodResultsCard({required this.record, super.key});
  final AuthorizedClinicalRecord record;

  @override
  Widget build(BuildContext context) {
    final labs = record
        .entriesOf(ClinicalSectionType.observations)
        .where((e) => e.category == 'laboratory' && _instant(e) != null);
    final takes = <DateTime, List<ClinicalRecordEntry>>{};
    for (final entry in labs) {
      (takes[_instant(entry)!] ??= []).add(entry);
    }
    final ordered = takes.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return _SectionCard(
      title: 'Exámenes de sangre',
      children: [
        if (ordered.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Sin resultados registrados.',
              style: ClinicalTextStyles.subhead,
            ),
          )
        else
          _Expandable(
            label:
                'Ver resultados · ${ordered.length} ${ordered.length == 1 ? 'toma' : 'tomas'}',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final take in ordered)
                  _Tile(
                    alert: take.value.any((e) => e.isAbnormal),
                    lines: [
                      'Toma de las ${formatClinicalDateTime(take.key)}',
                      for (final entry in take.value)
                        '${entry.title} · ${entry.value ?? 'sin valor'}${entry.isAbnormal ? ' (${entry.flag!.label.toLowerCase()})' : ''}',
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Horario de medicamentos: hora programada y administración registrada.
class MedicationScheduleCard extends StatelessWidget {
  const MedicationScheduleCard({required this.record, super.key});
  final AuthorizedClinicalRecord record;

  @override
  Widget build(BuildContext context) {
    final doses = record.entriesOf(ClinicalSectionType.administrations);
    return _SectionCard(
      title: 'Horario de medicamentos',
      children: [
        const SizedBox(height: 4),
        if (doses.isEmpty)
          const Text(
            'Sin medicamentos programados.',
            style: ClinicalTextStyles.subhead,
          )
        else
          for (final dose in doses)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ClinicalColors.canvas,
                borderRadius: BorderRadius.circular(ClinicalRadii.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dose.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _Pair(
                          'Hora programada',
                          dose.date == null ? 'Sin hora' : _timeOf(dose),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Pair(
                          'Administración registrada',
                          dose.administeredAt == null
                              ? 'Sin registro'
                              : formatClinicalDateTime(
                                  DateTime.parse(dose.administeredAt!),
                                ),
                          alert: dose.administeredAt == null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

class _Pair extends StatelessWidget {
  const _Pair(this.label, this.value, {this.alert = false});
  final String label;
  final String value;
  final bool alert;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: ClinicalTextStyles.footnote),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: alert ? ClinicalColors.attention : ClinicalColors.ink,
        ),
      ),
    ],
  );
}

double _millilitres(ClinicalRecordEntry entry) =>
    double.tryParse((entry.value ?? '').split(' ').first) ?? 0;

/// Balance hídrico: ingresos, egresos y neto del registro disponible.
class FluidBalanceCard extends StatelessWidget {
  const FluidBalanceCard({required this.record, super.key});
  final AuthorizedClinicalRecord record;

  @override
  Widget build(BuildContext context) {
    final observations = record.entriesOf(ClinicalSectionType.observations);
    final intake = observations.where((e) => e.category == _fluidIntake);
    final output = observations.where((e) => e.category == _fluidOutput);
    final totalIn = intake.fold<double>(0, (sum, e) => sum + _millilitres(e));
    final totalOut = output.fold<double>(0, (sum, e) => sum + _millilitres(e));
    final net = totalIn - totalOut;
    String ml(double value) => '${value.round()} mL';
    return _SectionCard(
      title: 'Balance hídrico',
      children: [
        const SizedBox(height: 2),
        const Text(
          'Registro de ingresos y egresos del episodio',
          style: ClinicalTextStyles.footnote,
        ),
        if (intake.isEmpty && output.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Sin ingresos ni egresos registrados.',
              style: ClinicalTextStyles.subhead,
            ),
          )
        else ...[
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Pair('Ingresos', ml(totalIn))),
              Expanded(child: _Pair('Egresos', ml(totalOut))),
              Expanded(
                child: _Pair('Balance neto', '${net > 0 ? '+' : ''}${ml(net)}'),
              ),
            ],
          ),
          _Expandable(
            label: 'Ver registros',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final entry in [...intake, ...output])
                  _Tile(
                    lines: [
                      '${entry.category == _fluidIntake ? 'Ingreso' : 'Egreso'} · ${entry.title}',
                      '${entry.value ?? ''} · ${_timeOf(entry)}',
                    ],
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Observaciones relevantes: valores alterados agrupados por tipo.
class RelevantObservations extends StatelessWidget {
  const RelevantObservations({required this.record, super.key});
  final AuthorizedClinicalRecord record;

  @override
  Widget build(BuildContext context) {
    final abnormal = record
        .entriesOf(ClinicalSectionType.observations)
        .where((e) => e.isAbnormal)
        .toList();
    final groups = <String, List<ClinicalRecordEntry>>{};
    for (final entry in abnormal) {
      final group = switch (entry.category) {
        'vital-signs' => 'Signos vitales',
        'laboratory' => 'Exámenes',
        _ => 'Otras observaciones',
      };
      (groups[group] ??= []).add(entry);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Observaciones relevantes',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        if (groups.isEmpty)
          const Text(
            'Sin observaciones relevantes registradas.',
            style: ClinicalTextStyles.subhead,
          )
        else
          for (final group in groups.entries)
            _Tile(
              alert: true,
              lines: [
                '${group.key} · ${group.value.length}',
                for (final entry in group.value.take(4))
                  '${_timeOf(entry)} · ${entry.title}: ${entry.value ?? ''} (${entry.flag!.label.toLowerCase()})',
              ],
            ),
      ],
    );
  }
}

/// "Ver foto adjunta": downloads the photo through the gateway on demand.
class ClinicalPhotoAttachment extends ConsumerStatefulWidget {
  const ClinicalPhotoAttachment({
    required this.hospitalizationId,
    required this.documentId,
    super.key,
  });
  final String hospitalizationId;
  final String documentId;

  @override
  ConsumerState<ClinicalPhotoAttachment> createState() =>
      _ClinicalPhotoAttachmentState();
}

class _ClinicalPhotoAttachmentState
    extends ConsumerState<ClinicalPhotoAttachment> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final key = (
      hospitalizationId: widget.hospitalizationId,
      documentId: widget.documentId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 36),
            ),
            onPressed: () => setState(() => _open = !_open),
            icon: const Icon(Icons.photo_outlined, size: 18),
            label: Text(_open ? 'Ocultar foto adjunta' : 'Ver foto adjunta'),
          ),
        ),
        if (_open)
          ref
              .watch(clinicalPhotoProvider(key))
              .when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const Text(
                  'No se pudo cargar la foto.',
                  style: TextStyle(color: ClinicalColors.destructive),
                ),
                data: (photo) => photo == null
                    ? const Text('Foto no disponible.')
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(
                          ClinicalRadii.control,
                        ),
                        child: Image.memory(
                          Uint8List.fromList(photo.bytes),
                          fit: BoxFit.cover,
                          semanticLabel: 'Foto clínica adjunta',
                        ),
                      ),
              ),
      ],
    );
  }
}

/// Category and role shown for a note in the timeline.
({String category, ClinicalTint tint}) noteCategory(String? wire) {
  final category = EventCategory.fromWire(wire) ?? EventCategory.notaClinica;
  return (category: category.label, tint: category.tint);
}
