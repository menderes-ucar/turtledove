class NameCityAnimalRoundResult {
  final String userId;
  final String name;
  final String city;
  final String animal;
  final String plant;
  final String thing;
  final String country;
  final bool nameValid;
  final bool cityValid;
  final bool animalValid;
  final bool plantValid;
  final bool thingValid;
  final bool countryValid;
  final bool? nameReview;
  final bool? cityReview;
  final bool? animalReview;
  final bool? plantReview;
  final bool? thingReview;
  final bool? countryReview;
  final int points;

  const NameCityAnimalRoundResult({
    required this.userId,
    required this.name,
    required this.city,
    required this.animal,
    required this.plant,
    required this.thing,
    required this.country,
    required this.nameValid,
    required this.cityValid,
    required this.animalValid,
    required this.plantValid,
    required this.thingValid,
    required this.countryValid,
    required this.nameReview,
    required this.cityReview,
    required this.animalReview,
    required this.plantReview,
    required this.thingReview,
    required this.countryReview,
    required this.points,
  });

  factory NameCityAnimalRoundResult.fromMap(Map<String, dynamic> map) {
    bool? nullableBool(dynamic value) => value == null ? null : value == true;

    return NameCityAnimalRoundResult(
      userId: map['user_id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      city: map['city']?.toString() ?? '',
      animal: map['animal']?.toString() ?? '',
      plant: map['plant']?.toString() ?? '',
      thing: map['thing']?.toString() ?? '',
      country: map['country']?.toString() ?? '',
      nameValid: map['name_valid'] == true,
      cityValid: map['city_valid'] == true,
      animalValid: map['animal_valid'] == true,
      plantValid: map['plant_valid'] == true,
      thingValid: map['thing_valid'] == true,
      countryValid: map['country_valid'] == true,
      nameReview: nullableBool(map['name_review']),
      cityReview: nullableBool(map['city_review']),
      animalReview: nullableBool(map['animal_review']),
      plantReview: nullableBool(map['plant_review']),
      thingReview: nullableBool(map['thing_review']),
      countryReview: nullableBool(map['country_review']),
      points: (map['points'] as num?)?.toInt() ?? 0,
    );
  }

  bool get reviewComplete =>
      nameReview != null &&
      cityReview != null &&
      animalReview != null &&
      plantReview != null &&
      thingReview != null &&
      countryReview != null;
}

class NameCityAnimalState {
  final String sessionId;
  final String createdBy;
  final String partnerId;
  final String languageCode;
  final String currentLetter;
  final int roundNumber;
  final int totalRounds;
  final String status;
  final String phase;
  final DateTime? roundDeadlineAt;
  final String? winnerUserId;
  final bool createdReady;
  final bool partnerReady;
  final int createdScore;
  final int partnerScore;
  final bool submittedByMe;
  final bool submittedByPartner;
  final bool myReviewComplete;
  final bool partnerReviewComplete;
  final List<NameCityAnimalRoundResult> roundResults;

  const NameCityAnimalState({
    required this.sessionId,
    required this.createdBy,
    required this.partnerId,
    required this.languageCode,
    required this.currentLetter,
    required this.roundNumber,
    required this.totalRounds,
    required this.status,
    required this.phase,
    required this.roundDeadlineAt,
    required this.winnerUserId,
    required this.createdReady,
    required this.partnerReady,
    required this.createdScore,
    required this.partnerScore,
    required this.submittedByMe,
    required this.submittedByPartner,
    required this.myReviewComplete,
    required this.partnerReviewComplete,
    required this.roundResults,
  });

  factory NameCityAnimalState.fromMap(
    Map<String, dynamic> map, {
    String? currentUserId,
  }) {
    final me = currentUserId ?? '';
    final createdBy = map['created_by']?.toString() ?? '';

    return NameCityAnimalState(
      sessionId: map['session_id']?.toString() ?? '',
      createdBy: createdBy,
      partnerId: map['partner_id']?.toString() ?? '',
      languageCode: map['language_code']?.toString() ?? 'en',
      currentLetter: map['current_letter']?.toString() ?? '',
      roundNumber: (map['round_number'] as num?)?.toInt() ?? 1,
      totalRounds: (map['total_rounds'] as num?)?.toInt() ?? 5,
      status: map['status']?.toString() ?? 'waiting',
      phase: map['phase']?.toString() ?? 'answering',
      roundDeadlineAt: DateTime.tryParse(
        map['round_deadline_at']?.toString() ?? '',
      ),
      winnerUserId: map['winner_user_id']?.toString(),
      createdReady: map['created_ready'] == true,
      partnerReady: map['partner_ready'] == true,
      createdScore: (map['created_score'] as num?)?.toInt() ?? 0,
      partnerScore: (map['partner_score'] as num?)?.toInt() ?? 0,
      submittedByMe: me == createdBy
          ? map['created_submitted'] == true
          : map['partner_submitted'] == true,
      submittedByPartner: me == createdBy
          ? map['partner_submitted'] == true
          : map['created_submitted'] == true,
      myReviewComplete: map['my_review_complete'] == true,
      partnerReviewComplete: map['partner_review_complete'] == true,
      roundResults: ((map['round_results'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => NameCityAnimalRoundResult.fromMap(
                Map<String, dynamic>.from(e),
              ))
          .toList(growable: false),
    );
  }

  bool get isWaiting => status == 'waiting';
  bool get isPlaying => status == 'playing';
  bool get isReviewing => status == 'playing' && phase == 'reviewing';
  bool get isAnswering => status == 'playing' && phase == 'answering';
  bool get isCompleted => status == 'completed';
}

extension NameCityAnimalScoreX on NameCityAnimalState {
  int myScoreFor(String userId) => userId == createdBy ? createdScore : partnerScore;
  int opponentScoreFor(String userId) => userId == createdBy ? partnerScore : createdScore;
}
