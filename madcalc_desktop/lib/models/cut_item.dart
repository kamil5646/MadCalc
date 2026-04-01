class CutItem {
  CutItem({
    required this.id,
    required this.lengthMm,
    required this.quantity,
  });

  final String id;
  final int lengthMm;
  final int quantity;

  int get totalLengthMm => lengthMm * quantity;

  CutItem copyWith({
    String? id,
    int? lengthMm,
    int? quantity,
  }) {
    return CutItem(
      id: id ?? this.id,
      lengthMm: lengthMm ?? this.lengthMm,
      quantity: quantity ?? this.quantity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lengthMm': lengthMm,
      'quantity': quantity,
    };
  }

  factory CutItem.fromJson(Map<String, dynamic> json) {
    return CutItem(
      id: json['id'] as String,
      lengthMm: json['lengthMm'] as int,
      quantity: json['quantity'] as int,
    );
  }
}
