import 'dart:async';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../core/theme/app_theme.dart';
import 'common_widgets.dart';

/// Picks the recogniser locale from the device's list, in order of
/// preference: bn_BD → bn_IN → any bn → en_IN → [systemLocaleId] → first.
/// Accepts both `bn_BD` and `bn-BD` spellings. Pure, for unit tests.
String? pickVoiceLocale(List<String> localeIds, {String? systemLocaleId}) {
  if (localeIds.isEmpty) return systemLocaleId;
  String norm(String id) => id.replaceAll('-', '_').toLowerCase();
  String? exact(String want) {
    for (final id in localeIds) {
      if (norm(id) == want) return id;
    }
    return null;
  }

  String? prefix(String want) {
    for (final id in localeIds) {
      final n = norm(id);
      if (n == want || n.startsWith('${want}_')) return id;
    }
    return null;
  }

  return exact('bn_bd') ??
      exact('bn_in') ??
      prefix('bn') ??
      exact('en_in') ??
      (systemLocaleId != null && localeIds.any((id) => norm(id) == norm(systemLocaleId)) ? systemLocaleId : null) ??
      localeIds.first;
}

/// Bangla message for a speech_to_text error code; null for ignorable ones.
String? voiceErrorBn(String errorMsg) {
  switch (errorMsg) {
    case 'error_network':
    case 'error_network_timeout':
    case 'error_server':
      return 'ইন্টারনেট দরকার — Google Speech অফলাইনে বাংলা বোঝে না';
    case 'error_no_match':
    case 'error_speech_timeout':
      return 'কিছু শোনা যায়নি, আবার বলুন';
    case 'error_permission':
    case 'error_audio_error':
      return 'মাইকের অনুমতি নেই। সেটিংসে গিয়ে অনুমতি দিন।';
    case 'error_busy':
    case 'error_client':
      return 'রেকগনাইজার ব্যস্ত। এক মুহূর্ত পর আবার চেষ্টা করুন।';
    case 'error_language_not_supported':
    case 'error_language_unavailable':
      return 'এই ফোনে বাংলা স্পিচ পাওয়া যায়নি। Google অ্যাপে বাংলা ভাষা যোগ করুন।';
    default:
      return 'শোনা যায়নি। আবার চেষ্টা করুন।';
  }
}

/// Reusable voice capture sheet. Uses the device's (Google) speech recogniser
/// through speech_to_text with Bangla first, then falls back to bn / en_IN.
/// Returns the final transcript, or null when cancelled.
class VoiceSheet extends StatefulWidget {
  final String title;
  final String hint;
  final List<String> examples;
  const VoiceSheet({super.key, required this.title, required this.hint, this.examples = const []});

  static Future<String?> listen(
    BuildContext context, {
    String title = 'মুখে বলুন',
    String hint = 'মাইকে চাপ দিয়ে বলুন',
    List<String> examples = const [],
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusXl))),
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.9),
        child: VoiceSheet(title: title, hint: hint, examples: examples),
      ),
    );
  }

  @override
  State<VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<VoiceSheet> with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  late final AnimationController _pulse;
  bool _available = false;
  bool _listening = false;
  bool _initDone = false;
  bool _permissionDenied = false;
  String _text = '';
  bool _gotFinal = false;
  String? _localeId;
  String _localeName = '';
  String _error = '';

  /// 0..1 normalised mic level from onSoundLevelChange (Android gives dB
  /// roughly -2..10; iOS roughly -50..0).
  double _level = 0;
  DateTime? _listenStartedAt;
  bool _autoRestarted = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900), lowerBound: 0.92, upperBound: 1.12)..repeat(reverse: true);
    _init();
  }

  @override
  void dispose() {
    _speech.stop();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _error = '';
    _permissionDenied = false;
    try {
      // initialize() requests RECORD_AUDIO on Android; its result must be
      // awaited and checked — calling listen() before it resolves is the
      // usual cause of "it just doesn't hear me".
      final ok = await _speech.initialize(
        onStatus: _onStatus,
        onError: _onError,
        debugLogging: false,
      );
      _available = ok;
      if (!ok) {
        final perm = await _speech.hasPermission;
        _permissionDenied = !perm;
        _error = perm ? 'এই ফোনে ভয়েস রেকগনিশন পাওয়া যায়নি। Google অ্যাপ আপডেট করুন।' : 'মাইকের অনুমতি দরকার।';
      } else {
        final locales = await _speech.locales();
        final sys = await _speech.systemLocale();
        _localeId = pickVoiceLocale(locales.map((l) => l.localeId).toList(), systemLocaleId: sys?.localeId);
        _localeName = locales.where((l) => l.localeId == _localeId).map((l) => l.name).firstOrNull ?? (_localeId ?? '');
      }
    } catch (e) {
      _available = false;
      _error = 'এই ফোনে ভয়েস সাপোর্ট পাওয়া যায়নি।';
    }
    if (mounted) {
      setState(() => _initDone = true);
      if (_available) _start();
    }
  }

  void _onStatus(String s) {
    if (!mounted) return;
    if (s == stt.SpeechToText.listeningStatus) {
      setState(() => _listening = true);
      return;
    }
    if (s == stt.SpeechToText.doneStatus || s == stt.SpeechToText.notListeningStatus) {
      final started = _listenStartedAt;
      final early = started != null && DateTime.now().difference(started) < const Duration(seconds: 3);
      // Some recognisers stop immediately once after a cold start; retry
      // once automatically so the user does not have to tap again.
      if (early && !_gotFinal && _text.isEmpty && !_autoRestarted && _error.isEmpty) {
        _autoRestarted = true;
        setState(() => _listening = false);
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (mounted && !_listening) _start(keepText: true);
        });
        return;
      }
      setState(() {
        _listening = false;
        _level = 0;
      });
    }
  }

  void _onError(SpeechRecognitionError e) {
    if (!mounted) return;
    final msg = voiceErrorBn(e.errorMsg);
    setState(() {
      _listening = false;
      _level = 0;
      if (e.errorMsg == 'error_permission') _permissionDenied = true;
      if (_text.isEmpty && msg != null) _error = msg;
    });
  }

  Future<void> _start({bool keepText = false}) async {
    if (!_available) return;
    setState(() {
      _listening = true;
      if (!keepText) {
        _text = '';
        _gotFinal = false;
        _autoRestarted = false;
      }
      _error = '';
      _level = 0;
    });
    _listenStartedAt = DateTime.now();
    try {
      await _speech.listen(
        onResult: (r) {
          if (!mounted) return;
          setState(() {
            if (r.recognizedWords.isNotEmpty) _text = r.recognizedWords;
            if (r.finalResult) _gotFinal = true;
          });
        },
        onSoundLevelChange: (level) {
          if (!mounted) return;
          // Android: ~-2 (silence) .. ~10 (loud). iOS: dB, -50..0.
          final n = level < -10 ? ((level + 50) / 50) : ((level + 2) / 12);
          setState(() => _level = n.clamp(0.0, 1.0));
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.dictation,
          localeId: _localeId,
          partialResults: true,
          cancelOnError: false,
          pauseFor: const Duration(seconds: 4),
          listenFor: const Duration(seconds: 30),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _listening = false;
          if (_text.isEmpty) _error = 'শোনা শুরু করা যায়নি। আবার চেষ্টা করুন।';
        });
      }
    }
  }

  Future<void> _stop() async {
    await _speech.stop();
    if (mounted) {
      setState(() {
        _listening = false;
        _level = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _listening ? AppTheme.coral : AppTheme.indigo;
    // Content scrolls; the action bar is pinned and sits above the keyboard.
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(AppTheme.gutter, AppTheme.s12, AppTheme.gutter, AppTheme.s16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: AppTheme.hairline, borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: Text(widget.title, style: AppTheme.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: AppTheme.inkMuted), visualDensity: VisualDensity.compact),
        ]),
        Text(widget.hint, style: AppTheme.caption),
        const SizedBox(height: 22),
        Center(
          child: GestureDetector(
            onTap: _listening ? _stop : _start,
            child: AnimatedBuilder(
              animation: _pulse,
              builder: (_, child) => Stack(alignment: Alignment.center, children: [
                if (_listening) ...[
                  // Live mic level: grows with the voice so the user can see
                  // the phone is actually hearing them.
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 90),
                    width: 96 + 90 * _level,
                    height: 96 + 90 * _level,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.10 + 0.15 * _level)),
                  ),
                  Transform.scale(
                    scale: _pulse.value * 1.35,
                    child: Container(width: 96, height: 96, decoration: BoxDecoration(shape: BoxShape.circle, color: color.withValues(alpha: 0.12))),
                  ),
                ],
                Transform.scale(
                  scale: _listening ? _pulse.value : 1,
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: _listening ? AppTheme.coral : AppTheme.indigo),
                    child: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded, color: Colors.white, size: 42),
                  ),
                ),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(
            !_initDone ? 'প্রস্তুত হচ্ছে…' : (!_available ? 'ভয়েস পাওয়া যাচ্ছে না' : (_listening ? 'শুনছি… বলুন' : 'মাইকে চাপ দিন')),
            style: AppTheme.bodySm.copyWith(color: color),
          ),
        ),
        if (_available && _localeName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Center(child: Text('ভাষা: $_localeName', style: AppTheme.caption)),
        ],
        if (_initDone && _permissionDenied) ...[
          const SizedBox(height: 8),
          Center(
            child: TonalButton(
              label: 'অনুমতি দিন',
              icon: Icons.mic_rounded,
              expanded: false,
              onPressed: () {
                setState(() => _initDone = false);
                _init();
              },
            ),
          ),
        ],
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Container(
            key: ValueKey(_text.isEmpty ? _error : _text),
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppTheme.sand, borderRadius: BorderRadius.circular(AppTheme.radiusMd)),
            child: Text(
              _text.isNotEmpty ? '“$_text”' : (_error.isNotEmpty ? _error : '…'),
              textAlign: TextAlign.center,
              style: AppTheme.body.copyWith(color: _text.isNotEmpty ? AppTheme.ink : AppTheme.inkHint),
            ),
          ),
        ),
        if (widget.examples.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('যেমন বলতে পারেন', style: AppTheme.sectionHeader),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.examples
                .map((e) => ActionChip(
                      label: Text(e),
                      onPressed: () => setState(() => _text = e),
                    ))
                .toList(),
          ),
        ],
      ]),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Flexible(child: SingleChildScrollView(child: body)),
        BottomActionBar(
          secondary: TonalButton(label: 'আবার বলুন', icon: Icons.refresh_rounded, expanded: false, onPressed: _available ? _start : null),
          primary: PrimaryButton(
            label: 'ঠিক আছে',
            onPressed: _text.trim().isEmpty
                ? null
                : () async {
                    await _speech.stop();
                    if (context.mounted) Navigator.pop(context, _text.trim());
                  },
          ),
        ),
      ]),
    );
  }
}

/// Small mic button that opens [VoiceSheet] and hands back the transcript.
class VoiceInputButton extends StatelessWidget {
  final ValueChanged<String> onResult;
  final String title;
  final String hint;
  final List<String> examples;
  final Color color;
  final double size;
  final bool filled;

  const VoiceInputButton({
    super.key,
    required this.onResult,
    this.title = 'মুখে বলুন',
    this.hint = 'মাইকে চাপ দিয়ে বলুন',
    this.examples = const [],
    this.color = AppTheme.indigo,
    this.size = 48,
    this.filled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'মুখে বলুন',
      child: Material(
        color: filled ? color.withValues(alpha: 0.10) : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () async {
            final text = await VoiceSheet.listen(context, title: title, hint: hint, examples: examples);
            if (text != null && text.isNotEmpty) onResult(text);
          },
          child: SizedBox(width: size, height: size, child: Icon(Icons.mic_rounded, color: color, size: size * 0.5)),
        ),
      ),
    );
  }
}
