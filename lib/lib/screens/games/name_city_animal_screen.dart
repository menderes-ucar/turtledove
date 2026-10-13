import 'package:bestie/models/name_city_animal_model.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../providers/auth_provider.dart';
import '../../../screens/games/name_city_animal_localization.dart';
import '../../../services/name_city_animal_service.dart';
import '../../providers/name_city_animal_provider.dart';

class NameCityAnimalLobbyScreen extends StatefulWidget {
  const NameCityAnimalLobbyScreen({super.key});

  @override
  State<NameCityAnimalLobbyScreen> createState() => _NameCityAnimalLobbyScreenState();
}

class _NameCityAnimalLobbyScreenState extends State<NameCityAnimalLobbyScreen> {
  String? _language;

  @override
  Widget build(BuildContext context) {
    if (_language == null) {
      return _LanguagePicker(
        onSelected: (language) => setState(() => _language = language),
      );
    }

    final profile = context.read<AuthProvider>().profile;
    final partnerId = profile?.pairedWith;
    if (partnerId == null || partnerId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(NameCityAnimalStrings.of(context).title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _localized(context, {
                'tr': 'Bu oyunu oynamak için önce partnerinle eşleşmelisin.',
                'en': 'Pair with your partner before starting this game.',
                'de': 'Kopple dich zuerst mit deinem Partner.',
                'es': 'Primero debes vincularte con tu pareja.',
                'fr': 'Associez-vous d’abord à votre partenaire.',
              }),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider(
      create: (_) => NameCityAnimalProvider(
        service: NameCityAnimalService(Supabase.instance.client),
        partnerId: partnerId,
        languageCode: _language!,
      ),
      child: const _NameCityAnimalBody(),
    );
  }

  String _localized(BuildContext context, Map<String, String> values) {
    final code = Localizations.localeOf(context).languageCode;
    return values[code] ?? values['en']!;
  }
}

class _LanguagePicker extends StatelessWidget {
  final ValueChanged<String> onSelected;
  const _LanguagePicker({required this.onSelected});

  static const languages = [
    ('tr', '🇹🇷', 'Türkçe'),
    ('en', '🇬🇧', 'English'),
    ('de', '🇩🇪', 'Deutsch'),
    ('es', '🇪🇸', 'Español'),
    ('fr', '🇫🇷', 'Français'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = NameCityAnimalStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(s.chooseLanguage, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(s.languageInfo),
          const SizedBox(height: 20),
          ...languages.map(
            (language) => Card(
              child: ListTile(
                leading: Text(language.$2, style: const TextStyle(fontSize: 28)),
                title: Text(language.$3),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onSelected(language.$1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NameCityAnimalBody extends StatelessWidget {
  const _NameCityAnimalBody();

  @override
  Widget build(BuildContext context) {
    return Consumer<NameCityAnimalProvider>(
      builder: (context, provider, _) {
        final state = provider.state;
        if (provider.isLoading || state == null) {
          return Scaffold(
            appBar: AppBar(title: Text(NameCityAnimalStrings.of(context).title)),
            body: provider.error == null
                ? const Center(child: CircularProgressIndicator())
                : _ErrorBody(error: provider.error!, onRetry: provider.retry),
          );
        }

        if (state.isCompleted) return _CompletedBody(state: state);
        if (state.isWaiting) return _ReadyBody(provider: provider);
        if (state.isReviewing) return _ReviewBody(provider: provider);
        return _PlayingBody(provider: provider);
      },
    );
  }
}

class _ReadyBody extends StatelessWidget {
  final NameCityAnimalProvider provider;
  const _ReadyBody({required this.provider});

  @override
  Widget build(BuildContext context) {
    final s = NameCityAnimalStrings.of(context);
    final state = provider.state!;
    return Scaffold(
      appBar: AppBar(title: Text('🎯 ${s.title}')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const Text('📝', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  Text(
                    state.createdReady && state.partnerReady ? s.bothReady : s.waiting,
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(s.languageInfo, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _ReadyPlayerCard(label: s.you, ready: provider.myReady),
          _ReadyPlayerCard(
            label: s.partner,
            ready: state.createdBy == provider.currentUserId ? state.partnerReady : state.createdReady,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: provider.isBusy ? null : provider.toggleReady,
            icon: Icon(provider.myReady ? Icons.close : Icons.check),
            label: Text(provider.myReady ? s.notReady : s.ready),
          ),
          if (provider.error != null) ...[
            const SizedBox(height: 12),
            Text(provider.error!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class _PlayingBody extends StatefulWidget {
  final NameCityAnimalProvider provider;
  const _PlayingBody({required this.provider});

  @override
  State<_PlayingBody> createState() => _PlayingBodyState();
}

class _PlayingBodyState extends State<_PlayingBody> {
  final _name = TextEditingController();
  final _city = TextEditingController();
  final _animal = TextEditingController();
  final _plant = TextEditingController();
  final _thing = TextEditingController();
  final _country = TextEditingController();
  int _lastRound = 0;

  @override
  void dispose() {
    _name.dispose();
    _city.dispose();
    _animal.dispose();
    _plant.dispose();
    _thing.dispose();
    _country.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final s = NameCityAnimalStrings.of(context);
    final state = p.state!;
    final submitted = state.submittedByMe;

    if (_lastRound != state.roundNumber) {
      _lastRound = state.roundNumber;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _name.clear();
        _city.clear();
        _animal.clear();
        _plant.clear();
        _thing.clear();
        _country.clear();
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('🎯 ${s.title}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: Text('${s.round} ${state.roundNumber}/${state.totalRounds}')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(child: _ScoreCard(label: s.you, score: state.myScoreFor(p.currentUserId ?? ''))),
              const SizedBox(width: 10),
              Expanded(child: _ScoreCard(label: s.partner, score: state.opponentScoreFor(p.currentUserId ?? ''))),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(s.letter, style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 2),
                  Text(state.currentLetter.toUpperCase(), style: Theme.of(context).textTheme.displayMedium),
                  const SizedBox(height: 4),
                  Text(p.remaining.inSeconds <= 0 ? s.timeUp : s.remaining(p.remaining.inSeconds)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _AnswerField(controller: _name, label: s.name, hint: s.enterName, enabled: !submitted, icon: Icons.person_outline),
          _AnswerField(controller: _city, label: s.city, hint: s.enterCity, enabled: !submitted, icon: Icons.location_city_outlined),
          _AnswerField(controller: _animal, label: s.animal, hint: s.enterAnimal, enabled: !submitted, icon: Icons.pets_outlined),
          _AnswerField(controller: _plant, label: s.plant, hint: s.enterPlant, enabled: !submitted, icon: Icons.local_florist_outlined),
          _AnswerField(controller: _thing, label: s.thing, hint: s.enterThing, enabled: !submitted, icon: Icons.category_outlined),
          _AnswerField(controller: _country, label: s.country, hint: s.enterCountry, enabled: !submitted, icon: Icons.public_outlined),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: submitted || p.isBusy
                ? null
                : () => p.submit(
                      name: _name.text,
                      city: _city.text,
                      animal: _animal.text,
                      plant: _plant.text,
                      thing: _thing.text,
                      country: _country.text,
                    ),
            icon: p.isBusy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: Text(s.submit),
          ),
          if (submitted) ...[
            const SizedBox(height: 14),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  state.submittedByPartner ? s.waitingReview : s.waitingOther,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: p.isBusy ? null : () => _confirmSurrender(context, p),
            icon: const Icon(Icons.flag_outlined),
            label: Text(s.surrender),
          ),
          if (p.error != null) ...[
            const SizedBox(height: 12),
            Text(p.error!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmSurrender(BuildContext context, NameCityAnimalProvider p) async {
    final s = NameCityAnimalStrings.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.surrenderQuestion),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.surrender)),
        ],
      ),
    );
    if (yes == true) await p.surrender();
  }
}

class _ReviewBody extends StatefulWidget {
  final NameCityAnimalProvider provider;
  const _ReviewBody({required this.provider});

  @override
  State<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends State<_ReviewBody> {
  final Map<String, bool> _reviews = {};
  int _reviewRound = 0;

  @override
  Widget build(BuildContext context) {
    final p = widget.provider;
    final state = p.state!;
    final s = NameCityAnimalStrings.of(context);
    final partnerId = state.createdBy == p.currentUserId ? state.partnerId : state.createdBy;
    NameCityAnimalRoundResult? partnerAnswer;
    for (final result in state.roundResults) {
      if (result.userId == partnerId) {
        partnerAnswer = result;
        break;
      }
    }

    if (_reviewRound != state.roundNumber) {
      _reviewRound = state.roundNumber;
      _reviews.clear();
    }

    if (partnerAnswer == null) {
      return Scaffold(
        appBar: AppBar(title: Text('🎯 ${s.title}')),
        body: Center(child: Text(s.waitingReview)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('🎯 ${s.title}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: Text('${s.round} ${state.roundNumber}/${state.totalRounds}')),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Text(s.reviewTitle, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(s.reviewInfo, textAlign: TextAlign.center),
          const SizedBox(height: 18),
          _ReviewRow(label: s.name, answer: partnerAnswer.name, valid: partnerAnswer.nameValid, value: _reviews['name'], onChanged: p.myReviewComplete ? null : (v) { if (v != null) setState(() => _reviews['name'] = v); }),
          _ReviewRow(label: s.city, answer: partnerAnswer.city, valid: partnerAnswer.cityValid, value: _reviews['city'], onChanged: p.myReviewComplete ? null : (v) { if (v != null) setState(() => _reviews['city'] = v); }),
          _ReviewRow(label: s.animal, answer: partnerAnswer.animal, valid: partnerAnswer.animalValid, value: _reviews['animal'], onChanged: p.myReviewComplete ? null : (v) { if (v != null) setState(() => _reviews['animal'] = v); }),
          _ReviewRow(label: s.plant, answer: partnerAnswer.plant, valid: partnerAnswer.plantValid, value: _reviews['plant'], onChanged: p.myReviewComplete ? null : (v) { if (v != null) setState(() => _reviews['plant'] = v); }),
          _ReviewRow(label: s.thing, answer: partnerAnswer.thing, valid: partnerAnswer.thingValid, value: _reviews['thing'], onChanged: p.myReviewComplete ? null : (v) { if (v != null) setState(() => _reviews['thing'] = v); }),
          _ReviewRow(label: s.country, answer: partnerAnswer.country, valid: partnerAnswer.countryValid, value: _reviews['country'], onChanged: p.myReviewComplete ? null : (v) { if (v != null) setState(() => _reviews['country'] = v); }),
          const SizedBox(height: 18),
          if (!p.myReviewComplete)
            FilledButton.icon(
              onPressed: p.isBusy || _reviews.length != 6
                  ? null
                  : () => p.review(Map<String, bool>.from(_reviews)),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(s.confirmReview),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  state.partnerReviewComplete ? s.reviewComplete : s.waitingPartnerReview,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          const SizedBox(height: 18),
          Text(s.systemValidationInfo, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          if (p.error != null) ...[
            const SizedBox(height: 12),
            Text(p.error!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  final String label;
  final String answer;
  final bool valid;
  final bool? value;
  final ValueChanged<bool?>? onChanged;

  const _ReviewRow({
    required this.label,
    required this.answer,
    required this.valid,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(answer.isEmpty ? '—' : answer),
                  const SizedBox(height: 3),
                  Text(valid ? '✓ Sistem: geçerli' : '✕ Sistem: geçersiz'),
                ],
              ),
            ),
            if (onChanged != null)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Kabul et',
                    onPressed: () => onChanged!(true),
                    icon: Icon(Icons.check_circle, color: value == true ? Colors.green : Colors.grey),
                  ),
                  IconButton(
                    tooltip: 'Reddet',
                    onPressed: () => onChanged!(false),
                    icon: Icon(Icons.cancel, color: value == false ? Colors.red : Colors.grey),
                  ),
                ],
              )
            else
              Icon(value == true ? Icons.check_circle : Icons.pending, color: value == true ? Colors.green : Colors.orange),
          ],
        ),
      ),
    );
  }
}

class _CompletedBody extends StatelessWidget {
  final NameCityAnimalState state;
  const _CompletedBody({required this.state});

  @override
  Widget build(BuildContext context) {
    final s = NameCityAnimalStrings.of(context);
    final winner = state.winnerUserId;
    final me = Supabase.instance.client.auth.currentUser?.id;
    final title = winner == null
        ? s.tie
        : winner == me
            ? s.you
            : s.partner;

    return Scaffold(
      appBar: AppBar(title: Text(s.completed)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.emoji_events_outlined, size: 72),
              const SizedBox(height: 16),
              Text('${s.winner}: $title', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text('${s.you}: ${state.myScoreFor(me ?? '')}  •  ${s.partner}: ${state.opponentScoreFor(me ?? '')}'),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.home)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String error;
  final Future<void> Function() onRetry;
  const _ErrorBody({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final s = NameCityAnimalStrings.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 52),
            const SizedBox(height: 16),
            Text(s.error, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: Text(s.retry)),
          ],
        ),
      ),
    );
  }
}

class _ReadyPlayerCard extends StatelessWidget {
  final String label;
  final bool ready;
  const _ReadyPlayerCard({required this.label, required this.ready});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(ready ? Icons.check_circle : Icons.hourglass_empty),
        title: Text(label),
        trailing: Text(ready ? '✓' : '…', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  final String label;
  final int score;
  const _ScoreCard({required this.label, required this.score});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(children: [Text(label), const SizedBox(height: 4), Text('$score', style: Theme.of(context).textTheme.headlineSmall)]),
      ),
    );
  }
}

class _AnswerField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool enabled;
  final IconData icon;
  const _AnswerField({required this.controller, required this.label, required this.hint, required this.enabled, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        enabled: enabled,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon), border: const OutlineInputBorder()),
      ),
    );
  }
}
