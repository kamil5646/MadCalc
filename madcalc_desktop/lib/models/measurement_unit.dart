enum MeasurementUnit {
  centimeters,
  millimeters;

  String get label {
    switch (this) {
      case MeasurementUnit.centimeters:
        return 'cm';
      case MeasurementUnit.millimeters:
        return 'mm';
    }
  }

  double get millimetersPerUnit {
    switch (this) {
      case MeasurementUnit.centimeters:
        return 10;
      case MeasurementUnit.millimeters:
        return 1;
    }
  }

  int? parse(String rawValue) {
    final normalized = rawValue.trim().replaceAll(',', '.');
    if (normalized.isEmpty) {
      return null;
    }

    final value = double.tryParse(normalized);
    if (value == null) {
      return null;
    }

    return (value * millimetersPerUnit).round();
  }

  String format(int valueMm, {bool includeUnit = true}) {
    final String value;
    switch (this) {
      case MeasurementUnit.millimeters:
        value = '$valueMm';
      case MeasurementUnit.centimeters:
        final centimeters = valueMm / millimetersPerUnit;
        value = valueMm % 10 == 0
            ? centimeters.toStringAsFixed(0)
            : centimeters.toStringAsFixed(1).replaceAll('.', ',');
    }

    return includeUnit ? '$value $label' : value;
  }

  static MeasurementUnit fromRaw(String rawValue) {
    return values.firstWhere(
      (unit) => unit.name == rawValue,
      orElse: () => MeasurementUnit.centimeters,
    );
  }
}
