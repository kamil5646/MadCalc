import 'bar_plan.dart';

class OptimizationResult {
  OptimizationResult({
    required this.barCount,
    required this.totalWasteMm,
    required this.utilizationPercent,
    required this.bars,
  });

  final int barCount;
  final int totalWasteMm;
  final double utilizationPercent;
  final List<BarPlan> bars;

  OptimizationResult copyWith({
    int? barCount,
    int? totalWasteMm,
    double? utilizationPercent,
    List<BarPlan>? bars,
  }) {
    return OptimizationResult(
      barCount: barCount ?? this.barCount,
      totalWasteMm: totalWasteMm ?? this.totalWasteMm,
      utilizationPercent: utilizationPercent ?? this.utilizationPercent,
      bars: bars ?? this.bars,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'barCount': barCount,
      'totalWasteMm': totalWasteMm,
      'utilizationPercent': utilizationPercent,
      'bars': bars.map((bar) => bar.toJson()).toList(),
    };
  }

  factory OptimizationResult.fromJson(Map<String, dynamic> json) {
    return OptimizationResult(
      barCount: json['barCount'] as int,
      totalWasteMm: json['totalWasteMm'] as int,
      utilizationPercent: (json['utilizationPercent'] as num).toDouble(),
      bars: (json['bars'] as List<dynamic>)
          .map((bar) => BarPlan.fromJson(Map<String, dynamic>.from(bar as Map)))
          .toList(),
    );
  }
}
