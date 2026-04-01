class BarPlan {
  BarPlan({
    required this.barIndex,
    required this.name,
    required this.cutsMm,
    required this.usedLengthMm,
    required this.wasteMm,
  });

  final int barIndex;
  final String name;
  final List<int> cutsMm;
  final int usedLengthMm;
  final int wasteMm;

  int get id => barIndex;

  int get cutCount => cutsMm.length;

  int get totalCutsLengthMm => cutsMm.fold(0, (sum, cut) => sum + cut);

  String get displayName {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'Sztanga $barIndex' : trimmed;
  }

  BarPlan copyWith({
    int? barIndex,
    String? name,
    List<int>? cutsMm,
    int? usedLengthMm,
    int? wasteMm,
  }) {
    return BarPlan(
      barIndex: barIndex ?? this.barIndex,
      name: name ?? this.name,
      cutsMm: cutsMm ?? this.cutsMm,
      usedLengthMm: usedLengthMm ?? this.usedLengthMm,
      wasteMm: wasteMm ?? this.wasteMm,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'barIndex': barIndex,
      'name': name,
      'cutsMm': cutsMm,
      'usedLengthMm': usedLengthMm,
      'wasteMm': wasteMm,
    };
  }

  factory BarPlan.fromJson(Map<String, dynamic> json) {
    return BarPlan(
      barIndex: json['barIndex'] as int,
      name: json['name'] as String? ?? '',
      cutsMm: (json['cutsMm'] as List<dynamic>).cast<int>(),
      usedLengthMm: json['usedLengthMm'] as int,
      wasteMm: json['wasteMm'] as int,
    );
  }
}
