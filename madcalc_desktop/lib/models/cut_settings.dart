class CutSettings {
  const CutSettings({
    required this.stockLengthMm,
    required this.sawThicknessMm,
  });

  final int stockLengthMm;
  final int sawThicknessMm;

  Map<String, dynamic> toJson() {
    return {
      'stockLengthMm': stockLengthMm,
      'sawThicknessMm': sawThicknessMm,
    };
  }

  factory CutSettings.fromJson(Map<String, dynamic> json) {
    return CutSettings(
      stockLengthMm: json['stockLengthMm'] as int,
      sawThicknessMm: json['sawThicknessMm'] as int,
    );
  }
}
