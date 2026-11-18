import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/locale_provider.dart';
import 'preview_strings.dart';

/// Public, account-free feature tour.
///
/// Everything here is local sample data: no network calls, no sign-in, no
/// pairing. It exists so that anyone (including App Review) can see every major
/// feature of Turtle Dove without needing a second account.
class PreviewScreen extends StatelessWidget {
  const PreviewScreen({super.key});

  static const routePath = '/preview';

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final features = <_Feature>[
      _Feature(Icons.favorite_rounded, const Color(0xFFE91E63), 'f_pair_t', 'f_pair_d', const _PairDemo()),
      _Feature(Icons.videocam_rounded, const Color(0xFF00897B), 'f_call_t', 'f_call_d', const _CallDemo()),
      _Feature(Icons.sports_esports_rounded, const Color(0xFF7C4DFF), 'f_games_t', 'f_games_d', const _GamesDemo()),
      _Feature(Icons.emoji_emotions_rounded, const Color(0xFFF9A825), 'f_mood_t', 'f_mood_d', const _MoodDemo()),
      _Feature(Icons.map_rounded, const Color(0xFF1E88E5), 'f_map_t', 'f_map_d', const _MapDemo()),
      _Feature(Icons.mail_rounded, const Color(0xFFFF7043), 'f_letters_t', 'f_letters_d', const _LettersDemo()),
      _Feature(Icons.hourglass_bottom_rounded, const Color(0xFF5E35B1), 'f_count_t', 'f_count_d', const _CountdownDemo()),
      _Feature(Icons.pets_rounded, const Color(0xFF43A047), 'f_pet_t', 'f_pet_d', const _PetDemo()),
      _Feature(Icons.forum_rounded, const Color(0xFF3949AB), 'f_topics_t', 'f_topics_d', const _TopicsDemo()),
    ];

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
              children: [
                _TopBar(strings: s),
                const SizedBox(height: 12),
                _Banner(text: s.t('banner')),
                const SizedBox(height: 22),
                Text(
                  s.t('hero_title'),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  s.t('hero_subtitle'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                _HowItWorks(strings: s),
                const SizedBox(height: 26),
                Text(
                  s.t('features_title'),
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                for (final f in features) ...[
                  _FeatureCard(feature: f, strings: s),
                  const SizedBox(height: 14),
                ],
                const SizedBox(height: 8),
                _CtaCard(strings: s),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Shell pieces
// ============================================================================

class _Feature {
  final IconData icon;
  final Color color;
  final String titleKey;
  final String descKey;
  final Widget demo;
  const _Feature(this.icon, this.color, this.titleKey, this.descKey, this.demo);
}

class _TopBar extends StatelessWidget {
  final PreviewStrings strings;
  const _TopBar({required this.strings});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: strings.t('exit_button'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.go('/splash'),
        ),
        const Spacer(),
        Icon(Icons.language_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Wrap(
          alignment: WrapAlignment.end,
          spacing: 6,
          children: [
            for (final code in PreviewStrings.supported)
              ChoiceChip(
                label: Text(code.toUpperCase()),
                selected: strings.code == code,
                visualDensity: VisualDensity.compact,
                showCheckmark: false,
                onSelected: (_) => context.read<LocaleProvider>().setLocale(code),
              ),
          ],
          ),
        ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String text;
  const _Banner({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_rounded, size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  final PreviewStrings strings;
  const _HowItWorks({required this.strings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = ['how_1', 'how_2', 'how_3'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.t('how_title'),
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            for (var i = 0; i < steps.length; i++) ...[
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(strings.t(steps[i]), style: const TextStyle(fontWeight: FontWeight.w600))),
                ],
              ),
              if (i != steps.length - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _Feature feature;
  final PreviewStrings strings;
  const _FeatureCard({required this.feature, required this.strings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  feature.color.withValues(alpha: 0.18),
                  feature.color.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: feature.color,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(feature.icon, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.t(feature.titleKey),
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        strings.t(feature.descKey),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        strings.t('sample_badge'),
                        style: TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strings.t('tap_to_try'),
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                feature.demo,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CtaCard extends StatelessWidget {
  final PreviewStrings strings;
  const _CtaCard({required this.strings});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            strings.t('cta_title'),
            style: theme.textTheme.titleLarge?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            strings.t('cta_body'),
            style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.92), height: 1.4),
          ),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.onPrimary,
              foregroundColor: scheme.primary,
            ),
            onPressed: () => context.go('/signup'),
            child: Text(strings.t('cta_button'), style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 6),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: scheme.onPrimary),
            onPressed: () => context.go('/splash'),
            child: Text(strings.t('exit_button')),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Demos (all local, no network)
// ============================================================================

class _DemoBox extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _DemoBox({required this.child, this.padding = const EdgeInsets.all(14)});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------- pairing

class _PairDemo extends StatefulWidget {
  const _PairDemo();

  @override
  State<_PairDemo> createState() => _PairDemoState();
}

class _PairDemoState extends State<_PairDemo> {
  bool _connected = false;

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return _DemoBox(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _Avatar(label: 'A', color: Color(0xFF7C4DFF)),
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                width: _connected ? 70 : 36,
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _connected ? const Color(0xFFE91E63) : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Icon(
                  _connected ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  key: ValueKey(_connected),
                  color: const Color(0xFFE91E63),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 350),
                width: _connected ? 70 : 36,
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: _connected ? const Color(0xFFE91E63) : scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _Avatar(label: 'B', color: _connected ? const Color(0xFF00897B) : scheme.outline),
            ],
          ),
          const SizedBox(height: 14),
          Text(s.t('demo_your_code'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          const Text(
            'A7K 2Q9',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 4),
          ),
          const SizedBox(height: 8),
          Text(
            _connected ? s.t('demo_connected') : s.t('demo_waiting'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => setState(() => _connected = !_connected),
            child: Text(s.t('demo_simulate')),
          ),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String label;
  final Color color;
  const _Avatar({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: color,
      child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
    );
  }
}

// ------------------------------------------------------------------ call

class _CallDemo extends StatefulWidget {
  const _CallDemo();

  @override
  State<_CallDemo> createState() => _CallDemoState();
}

class _CallDemoState extends State<_CallDemo> {
  Timer? _timer;
  int _seconds = 83;
  bool _muted = false;
  bool _cameraOff = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _clock {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFF1B2A3A), Color(0xFF0E1620)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 36,
            backgroundColor: Color(0xFF00897B),
            child: Text('A', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 10),
          const Text('Forever', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(
            '${s.t('demo_calling')} · $_clock',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _CallButton(
                icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                active: _muted,
                onTap: () => setState(() => _muted = !_muted),
              ),
              const SizedBox(width: 16),
              _CallButton(
                icon: _cameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
                active: _cameraOff,
                onTap: () => setState(() => _cameraOff = !_cameraOff),
              ),
              const SizedBox(width: 16),
              const _CallButton(icon: Icons.call_end_rounded, danger: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool danger;
  final VoidCallback? onTap;
  const _CallButton({required this.icon, this.active = false, this.danger = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = danger
        ? const Color(0xFFE53935)
        : active
            ? Colors.white
            : Colors.white.withValues(alpha: 0.14);
    final fg = (active && !danger) ? Colors.black87 : Colors.white;
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 48, height: 48, child: Icon(icon, color: fg)),
      ),
    );
  }
}

// ----------------------------------------------------------------- games

class _GamesDemo extends StatefulWidget {
  const _GamesDemo();

  @override
  State<_GamesDemo> createState() => _GamesDemoState();
}

class _GamesDemoState extends State<_GamesDemo> {
  int? _picked;

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final games = <(String, String)>[
      ('🧠', 'game_trivia'),
      ('🎯', 'game_most_likely'),
      ('🔤', 'game_word'),
      ('🌍', 'game_nca'),
      ('🃏', 'game_deck'),
    ];
    final answers = ['demo_trivia_a1', 'demo_trivia_a2', 'demo_trivia_a3'];

    return _DemoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in games)
                Chip(
                  avatar: Text(g.$1),
                  label: Text(s.t(g.$2), style: const TextStyle(fontWeight: FontWeight.w600)),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            s.t('demo_trivia_q'),
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < answers.length; i++) ...[
            _AnswerTile(
              text: s.t(answers[i]),
              state: _picked == i ? (i == 0 ? _AnswerState.correct : _AnswerState.wrong) : _AnswerState.idle,
              onTap: () => setState(() => _picked = i),
            ),
            const SizedBox(height: 8),
          ],
          if (_picked != null)
            Text(
              _picked == 0 ? s.t('demo_correct') : s.t('demo_wrong'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: _picked == 0 ? const Color(0xFF2E7D32) : scheme.error,
              ),
            ),
        ],
      ),
    );
  }
}

enum _AnswerState { idle, correct, wrong }

class _AnswerTile extends StatelessWidget {
  final String text;
  final _AnswerState state;
  final VoidCallback onTap;
  const _AnswerTile({required this.text, required this.state, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Color border = scheme.outlineVariant;
    Color fill = scheme.surface;
    IconData? icon;
    Color? iconColor;
    if (state == _AnswerState.correct) {
      border = const Color(0xFF2E7D32);
      fill = const Color(0xFF2E7D32).withValues(alpha: 0.12);
      icon = Icons.check_circle_rounded;
      iconColor = const Color(0xFF2E7D32);
    } else if (state == _AnswerState.wrong) {
      border = scheme.error;
      fill = scheme.error.withValues(alpha: 0.10);
      icon = Icons.cancel_rounded;
      iconColor = scheme.error;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
            if (icon != null) Icon(icon, color: iconColor, size: 20),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ mood

class _MoodDemo extends StatefulWidget {
  const _MoodDemo();

  @override
  State<_MoodDemo> createState() => _MoodDemoState();
}

class _MoodDemoState extends State<_MoodDemo> {
  int _selected = 0;

  static const _moods = <(String, String)>[
    ('😊', 'mood_happy'),
    ('😌', 'mood_calm'),
    ('😴', 'mood_tired'),
    ('🥰', 'mood_love'),
    ('😔', 'mood_sad'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return _DemoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('demo_you_feel'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < _moods.length; i++)
                GestureDetector(
                  onTap: () => setState(() => _selected = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _selected == i ? scheme.primaryContainer : Colors.transparent,
                      border: Border.all(
                        color: _selected == i ? scheme.primary : scheme.outlineVariant,
                        width: _selected == i ? 2 : 1,
                      ),
                    ),
                    child: AnimatedScale(
                      duration: const Duration(milliseconds: 200),
                      scale: _selected == i ? 1.18 : 1.0,
                      child: Text(_moods[i].$1, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            s.t(_moods[_selected].$2),
            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w800),
          ),
          const Divider(height: 26),
          Row(
            children: [
              const Text('🥰', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${s.t('demo_partner_feels')}: ${s.t('mood_love')}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- map

class _MapDemo extends StatefulWidget {
  const _MapDemo();

  @override
  State<_MapDemo> createState() => _MapDemoState();
}

class _MapDemoState extends State<_MapDemo> {
  int? _active;

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    final pins = <(double, double, String, Color)>[
      (0.18, 0.62, 'pin_home', const Color(0xFF7C4DFF)),
      (0.52, 0.30, 'pin_first_date', const Color(0xFFE91E63)),
      (0.82, 0.55, 'pin_next_trip', const Color(0xFFFF7043)),
    ];

    return _DemoBox(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: 200,
          child: LayoutBuilder(
            builder: (context, c) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _MapPainter(
                        grid: scheme.outlineVariant.withValues(alpha: 0.35),
                        route: const Color(0xFFE91E63).withValues(alpha: 0.6),
                        points: [
                          for (final p in pins) Offset(p.$1, p.$2),
                        ],
                      ),
                    ),
                  ),
                  for (var i = 0; i < pins.length; i++)
                    Positioned(
                      left: c.maxWidth * pins[i].$1 - 14,
                      top: c.maxHeight * pins[i].$2 - 34,
                      child: GestureDetector(
                        onTap: () => setState(() => _active = _active == i ? null : i),
                        child: Column(
                          children: [
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: _active == i ? 1 : 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: scheme.inverseSurface,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  s.t(pins[i].$3),
                                  style: TextStyle(color: scheme.onInverseSurface, fontSize: 11, fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            Icon(Icons.location_on_rounded, color: pins[i].$4, size: 32),
                          ],
                        ),
                      ),
                    ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.straighten_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            s.t('demo_distance'),
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  final Color grid;
  final Color route;
  final List<Offset> points;
  const _MapPainter({required this.grid, required this.route, required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(points[i].dx * size.width, points[i].dy * size.height);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        final prev = Offset(points[i - 1].dx * size.width, points[i - 1].dy * size.height);
        final mid = Offset((prev.dx + p.dx) / 2, (prev.dy + p.dy) / 2 - 24);
        path.quadraticBezierTo(mid.dx, mid.dy, p.dx, p.dy);
      }
    }

    final routePaint = Paint()
      ..color = route
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + 7;
        canvas.drawPath(metric.extractPath(distance, math.min(next, metric.length)), routePaint);
        distance += 13;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) =>
      old.grid != grid || old.route != route || old.points != points;
}

// --------------------------------------------------------------- letters

class _LettersDemo extends StatefulWidget {
  const _LettersDemo();

  @override
  State<_LettersDemo> createState() => _LettersDemoState();
}

class _LettersDemoState extends State<_LettersDemo> {
  bool _playing = false;

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return _DemoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF6E5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFE0A3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t('demo_letter_to'),
                  style: const TextStyle(
                    color: Color(0xFF4E342E),
                    fontWeight: FontWeight.w800,
                    fontStyle: FontStyle.italic,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  s.t('demo_letter_body'),
                  style: const TextStyle(color: Color(0xFF4E342E), height: 1.45),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => setState(() => _playing = !_playing),
            child: Container(
              padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: scheme.primary,
                    child: Icon(
                      _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: scheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        for (var i = 0; i < 18; i++)
                          Container(
                            width: 3,
                            height: 6.0 + ((i * 7) % 5) * 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            decoration: BoxDecoration(
                              color: scheme.onPrimaryContainer.withValues(alpha: _playing && i < 9 ? 1 : 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    s.t('demo_letter_voice').split('·').last.trim(),
                    style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            s.t('demo_letter_voice'),
            style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- countdown

class _CountdownDemo extends StatefulWidget {
  const _CountdownDemo();

  @override
  State<_CountdownDemo> createState() => _CountdownDemoState();
}

class _CountdownDemoState extends State<_CountdownDemo> {
  late final DateTime _target;
  Timer? _timer;
  Duration _left = Duration.zero;

  @override
  void initState() {
    super.initState();
    _target = DateTime.now().add(const Duration(days: 12, hours: 6, minutes: 24));
    _left = _target.difference(DateTime.now());
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left = _target.difference(DateTime.now()));
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final d = _left.isNegative ? Duration.zero : _left;

    Widget cell(int value, String unit) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Text(
                value.toString().padLeft(2, '0'),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              Text(unit, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return _DemoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.t('demo_until'), style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Row(
            children: [
              cell(d.inDays, s.t('unit_days')),
              const SizedBox(width: 8),
              cell(d.inHours % 24, s.t('unit_hours')),
              const SizedBox(width: 8),
              cell(d.inMinutes % 60, s.t('unit_minutes')),
              const SizedBox(width: 8),
              cell(d.inSeconds % 60, s.t('unit_seconds')),
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- pet

class _PetDemo extends StatefulWidget {
  const _PetDemo();

  @override
  State<_PetDemo> createState() => _PetDemoState();
}

class _PetDemoState extends State<_PetDemo> {
  double _happiness = 0.55;
  bool _bounce = false;

  void _feed() {
    setState(() {
      _happiness = (_happiness + 0.1).clamp(0.0, 1.0).toDouble();
      _bounce = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _bounce = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return _DemoBox(
      child: Column(
        children: [
          GestureDetector(
            onTap: _feed,
            child: AnimatedScale(
              duration: const Duration(milliseconds: 200),
              scale: _bounce ? 1.25 : 1.0,
              child: Container(
                width: 92,
                height: 92,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer,
                ),
                child: const Text('🕊️', style: TextStyle(fontSize: 46)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(s.t('demo_pet_feed'), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(s.t('demo_pet_happy'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _happiness,
                    minHeight: 10,
                    color: const Color(0xFFE91E63),
                    backgroundColor: scheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text('${(_happiness * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- topics

class _TopicsDemo extends StatefulWidget {
  const _TopicsDemo();

  @override
  State<_TopicsDemo> createState() => _TopicsDemoState();
}

class _TopicsDemoState extends State<_TopicsDemo> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final s = PreviewStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final keys = ['topic_1', 'topic_2', 'topic_3'];

    return _DemoBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Container(
              key: ValueKey(_index),
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                s.t(keys[_index]),
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _index = (_index + 1) % keys.length),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(s.t('demo_next_topic')),
            ),
          ),
        ],
      ),
    );
  }
}
