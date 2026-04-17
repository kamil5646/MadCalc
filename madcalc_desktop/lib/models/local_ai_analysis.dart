class LocalAiAnalysis {
  const LocalAiAnalysis({
    required this.score,
    required this.statusLabel,
    required this.headline,
    required this.summary,
    required this.highlights,
    required this.warnings,
    required this.suggestions,
  });

  final int score;
  final String statusLabel;
  final String headline;
  final String summary;
  final List<String> highlights;
  final List<String> warnings;
  final List<String> suggestions;

  bool get hasWarnings => warnings.isNotEmpty;
}
