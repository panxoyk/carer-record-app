import 'package:flutter/material.dart';

import 'clinical_tokens.dart';

/// A full-width, field-anchored selector whose menu is laid out below the field.
class AnchoredSelectorOption<T> {
  const AnchoredSelectorOption({required this.value, required this.label});

  final T value;
  final String label;
}

class AnchoredSelector<T> extends StatelessWidget {
  const AnchoredSelector({
    super.key,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    this.labelText,
    this.validator,
    this.decoration,
  });

  final List<AnchoredSelectorOption<T>> options;
  final T? selectedValue;
  final ValueChanged<T> onSelected;
  final String? labelText;
  final FormFieldValidator<T>? validator;
  final InputDecoration? decoration;

  @override
  Widget build(BuildContext context) => FormField<T>(
    key: ValueKey<T?>(selectedValue),
    initialValue: selectedValue,
    validator: validator,
    builder: (field) {
      final inputTheme = Theme.of(context).inputDecorationTheme;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownMenu<T>(
            key: ValueKey(field.value),
            expandedInsets: EdgeInsets.zero,
            initialSelection: field.value,
            label: labelText == null ? null : Text(labelText!),
            requestFocusOnTap: false,
            enableSearch: false,
            menuHeight: 320,
            menuStyle: MenuStyle(
              backgroundColor: const WidgetStatePropertyAll(Colors.white),
              surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
              elevation: const WidgetStatePropertyAll(8),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ClinicalRadii.card),
                ),
              ),
            ),
            inputDecorationTheme: inputTheme.copyWith(
              fillColor: decoration?.fillColor ?? inputTheme.fillColor,
              filled: decoration?.filled ?? inputTheme.filled,
            ),
            dropdownMenuEntries: [
              for (final option in options)
                DropdownMenuEntry(value: option.value, label: option.label),
            ],
            onSelected: (value) {
              if (value == null) return;
              field.didChange(value);
              onSelected(value);
            },
          ),
          if (field.errorText != null)
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4),
              child: Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      );
    },
  );
}
