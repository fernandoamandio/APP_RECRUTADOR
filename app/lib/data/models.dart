enum Eligibility { remoteBr, visaSponsor, uncertain, notEligible }

Eligibility eligibilityFrom(String? v) => switch (v) {
      'remote_br' => Eligibility.remoteBr,
      'visa_sponsor' => Eligibility.visaSponsor,
      'not_eligible' => Eligibility.notEligible,
      _ => Eligibility.uncertain,
    };

class SalarySuggestion {
  SalarySuggestion({
    required this.modality,
    required this.min,
    required this.target,
    required this.max,
    required this.currency,
    required this.warnings,
    required this.inputs,
  });

  final String modality; // relocation | remote
  final double min, target, max;
  final String currency;
  final List<String> warnings;
  final Map<String, dynamic> inputs;

  static SalarySuggestion? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    return SalarySuggestion(
      modality: j['modality'] as String,
      min: (j['min'] as num).toDouble(),
      target: (j['target'] as num).toDouble(),
      max: (j['max'] as num).toDouble(),
      currency: j['currency'] as String,
      warnings: List<String>.from(j['warnings'] ?? const []),
      inputs: Map<String, dynamic>.from(j['inputs'] ?? const {}),
    );
  }
}

class JobSourceLink {
  JobSourceLink(this.source, this.url);
  final String source;
  final String url;

  /// Nome exibido: as fontes exigem atribuição visível.
  String get label => switch (source) {
        'remoteok' => 'Remote OK',
        'weworkremotely' => 'We Work Remotely',
        'adzuna' => 'Adzuna',
        'jooble' => 'Jooble',
        _ => source,
      };
}

class JobMatch {
  JobMatch({
    required this.jobId,
    required this.title,
    required this.company,
    required this.location,
    required this.score,
    required this.reasons,
    required this.status,
    required this.eligibility,
    required this.evidence,
    required this.sponsorRegistered,
    required this.salary,
    required this.sources,
    required this.description,
  });

  final String jobId;
  final String title;
  final String company;
  final String location;
  final int score;
  final List<String> reasons;
  final String status;
  final Eligibility eligibility;
  final String? evidence;
  final bool sponsorRegistered;
  final SalarySuggestion? salary;
  final List<JobSourceLink> sources;
  final String description;

  /// Linha de job_matches com o join `jobs(*, job_eligibility(*), job_sources(*))`.
  factory JobMatch.fromRow(Map<String, dynamic> row) {
    final job = row['jobs'] as Map<String, dynamic>;
    final elig = job['job_eligibility'] as Map<String, dynamic>?;
    final city = job['city'] as String?;
    final country = job['country'] as String?;
    return JobMatch(
      jobId: job['id'] as String,
      title: job['title'] as String,
      company: job['company'] as String,
      location: [city, country].whereType<String>().where((s) => s.isNotEmpty).join(', ').ifEmpty('Remoto'),
      score: row['score'] as int,
      reasons: List<String>.from(row['reasons'] ?? const []),
      status: row['status'] as String,
      eligibility: eligibilityFrom(elig?['category'] as String?),
      evidence: elig?['evidence'] as String?,
      sponsorRegistered: (elig?['sponsor_registered'] as bool?) ?? false,
      salary: SalarySuggestion.fromJson(row['salary_suggested'] as Map<String, dynamic>?),
      sources: [
        for (final s in (job['job_sources'] as List? ?? const []))
          JobSourceLink(s['source'] as String, s['url'] as String),
      ],
      description: (job['description'] as String?) ?? '',
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
