import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/camera/application/camera_ui_state.dart' show PrefKeys;
import '../../features/cameras/domain/camera_spec.dart';
import '../monetization/pro.dart' show prefsOf;

/// How a skin is earned (the mini games; not wired up yet).
@immutable
class SkinUnlock {
  const SkinUnlock(this.game, this.goal);

  /// The Win98 program that gives it (Run name: SOL, BRICKS, PINBALL, MINES).
  final String game;

  /// What to do there, as the shop's price tag says it.
  final String goal;
}

/// A camera body's finish. The live 3D model shows its `finish.<id>` nodes
/// (tool/render/blender/export_glb.py FINISHES); the drawn bodies and the
/// shop use [covering] / [trim] / [shell] / [ink].
@immutable
class CameraSkin {
  const CameraSkin({
    required this.id,
    required this.mode,
    required this.name,
    required this.blurb,
    required this.covering,
    required this.trim,
    required this.shell,
    required this.ink,
    this.unlock,
  });

  final String id;
  final AppMode mode;
  final String name;
  final String blurb;

  /// The face: leatherette (film) or the front panel (digital).
  final Color covering;

  /// The top / bottom plates (film) or the trim (digital).
  final Color trim;

  /// The body's sides and back.
  final Color shell;

  /// Lettering on the plates.
  final Color ink;

  /// Null: owned from the start.
  final SkinUnlock? unlock;
}

/// Every skin, in shop order (the first of each mode is the default).
abstract final class CameraSkins {
  static const all = <CameraSkin>[
    CameraSkin(
      id: 'classic',
      mode: AppMode.film,
      name: 'Classic',
      blurb: 'Black leatherette, chrome plates. Where it all starts.',
      covering: Color(0xFF1E1916),
      trim: Color(0xFFD9DADC),
      shell: Color(0xFF111111),
      ink: Color(0xFF151515),
    ),
    CameraSkin(
      id: 'black',
      mode: AppMode.film,
      name: 'Black Paint',
      blurb: 'All black, white lettering. The pro body.',
      covering: Color(0xFF1E1916),
      trim: Color(0xFF1A1A1C),
      shell: Color(0xFF111111),
      ink: Color(0xFFE8E6E0),
      unlock: SkinUnlock('MINES', 'Clear a Minefield'),
    ),
    CameraSkin(
      id: 'brassed',
      mode: AppMode.film,
      name: 'Brassed',
      blurb: 'Black paint worn through to the brass. Twenty years of shooting.',
      covering: Color(0xFF1E1916),
      trim: Color(0xFF6E5530),
      shell: Color(0xFF3A2E1C),
      ink: Color(0xFFE8E6E0),
      unlock: SkinUnlock('PINBALL', 'Reach Commander in Space Rabbit'),
    ),
    CameraSkin(
      id: 'red',
      mode: AppMode.film,
      name: 'Red Leather',
      blurb: 'Chrome and red leatherette. Loud on purpose.',
      covering: Color(0xFF7A1D18),
      trim: Color(0xFFD9DADC),
      shell: Color(0xFF111111),
      ink: Color(0xFF151515),
      unlock: SkinUnlock('BRICKS', 'Clear 3 walls in Bricks'),
    ),
    CameraSkin(
      id: 'tan',
      mode: AppMode.film,
      name: 'Tan Leather',
      blurb: 'Chrome and saddle tan, like a travel camera.',
      covering: Color(0xFF8A5A2E),
      trim: Color(0xFFD9DADC),
      shell: Color(0xFF111111),
      ink: Color(0xFF151515),
      unlock: SkinUnlock('SOL', 'Win a game of Solitaire'),
    ),
    CameraSkin(
      id: 'green',
      mode: AppMode.film,
      name: 'Racing Green',
      blurb: 'Chrome and deep green leatherette.',
      covering: Color(0xFF1F4A2E),
      trim: Color(0xFFD9DADC),
      shell: Color(0xFF111111),
      ink: Color(0xFF151515),
      unlock: SkinUnlock('MINES', 'Win Minefield on Expert'),
    ),
    CameraSkin(
      id: 'mint',
      mode: AppMode.film,
      name: 'Mint',
      blurb: 'Mint and cream, a sixties compact.',
      covering: Color(0xFF9CC9B2),
      trim: Color(0xFFD9DADC),
      shell: Color(0xFFE6DAC0),
      ink: Color(0xFF151515),
      unlock: SkinUnlock('SOL', 'Win 5 games of Solitaire'),
    ),
    CameraSkin(
      id: 'cream',
      mode: AppMode.film,
      name: 'Cream',
      blurb: 'Cream leatherette on a mint body.',
      covering: Color(0xFFD8CCB0),
      trim: Color(0xFFD9DADC),
      shell: Color(0xFFA9D4BE),
      ink: Color(0xFF151515),
      unlock: SkinUnlock('BRICKS', 'Score 5,000 in Bricks'),
    ),
    CameraSkin(
      id: 'silver',
      mode: AppMode.digital,
      name: 'Silver',
      blurb: 'Brushed aluminium. Every camera shop window, 2003.',
      covering: Color(0xFFC5CAD1),
      trim: Color(0xFF8C939C),
      shell: Color(0xFF737A83),
      ink: Color(0xFF22262B),
    ),
    CameraSkin(
      id: 'grip',
      mode: AppMode.digital,
      name: 'Silver Grip',
      blurb: 'Silver with a rubber grip down the front.',
      covering: Color(0xFFC5CAD1),
      trim: Color(0xFF1F2023),
      shell: Color(0xFF737A83),
      ink: Color(0xFF22262B),
      unlock: SkinUnlock('BRICKS', 'Clear a wall in Bricks'),
    ),
    CameraSkin(
      id: 'gunmetal',
      mode: AppMode.digital,
      name: 'Gunmetal',
      blurb: 'Dark anodised metal. Serious.',
      covering: Color(0xFF4A4D52),
      trim: Color(0xFF2A2B2E),
      shell: Color(0xFF242528),
      ink: Color(0xFFDADDE2),
      unlock: SkinUnlock('PINBALL', 'Score 100,000 in Space Rabbit'),
    ),
    CameraSkin(
      id: 'champagne',
      mode: AppMode.digital,
      name: 'Champagne',
      blurb: 'Warm gold anodising, very Y2K.',
      covering: Color(0xFFD4BC93),
      trim: Color(0xFF8F7B5E),
      shell: Color(0xFF7A684F),
      ink: Color(0xFF3A2F22),
      unlock: SkinUnlock('SOL', 'Win Solitaire in under 3 minutes'),
    ),
    CameraSkin(
      id: 'twotone',
      mode: AppMode.digital,
      name: 'Two-Tone',
      blurb: 'Silver top, deep blue front.',
      covering: Color(0xFF1F3A78),
      trim: Color(0xFFC5CAD1),
      shell: Color(0xFF162A55),
      ink: Color(0xFFE3E6EA),
      unlock: SkinUnlock('MINES', 'Win Minefield on Intermediate'),
    ),
  ];

  static List<CameraSkin> forMode(AppMode mode) => [
    for (final s in all)
      if (s.mode == mode) s,
  ];

  static CameraSkin byId(AppMode mode, String? id) {
    final list = forMode(mode);
    return list.firstWhere((s) => s.id == id, orElse: () => list.first);
  }
}

/// The skin each body wears (film and digital), shared by the live 3D
/// model and the drawn bodies, so changing one changes both.
class CameraSkinNotifier extends Notifier<Map<AppMode, String>> {
  static String _key(AppMode mode) => mode == AppMode.digital ? PrefKeys.bodyFinish : PrefKeys.filmFinish;

  @override
  Map<AppMode, String> build() {
    final prefs = prefsOf(ref);
    return {for (final mode in AppMode.values) mode: CameraSkins.byId(mode, prefs?.getString(_key(mode))).id};
  }

  Future<void> set(AppMode mode, String id) async {
    state = {...state, mode: id};
    await prefsOf(ref)?.setString(_key(mode), id);
  }
}

final cameraSkinProvider = NotifierProvider<CameraSkinNotifier, Map<AppMode, String>>(CameraSkinNotifier.new);

/// Skins earned in the mini games (ids). The starting skins are always
/// owned. Until the games award them, Debug can unlock them all.
class UnlockedSkinsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => {...?prefsOf(ref)?.getStringList(PrefKeys.skinsUnlocked)};

  bool owns(CameraSkin skin) => skin.unlock == null || state.contains('${skin.mode.name}.${skin.id}');

  Future<void> unlock(CameraSkin skin) => _save({...state, '${skin.mode.name}.${skin.id}'});

  Future<void> unlockAll() => _save({for (final s in CameraSkins.all) '${s.mode.name}.${s.id}'});

  Future<void> lockAll() => _save({});

  Future<void> _save(Set<String> ids) async {
    state = ids;
    await prefsOf(ref)?.setStringList(PrefKeys.skinsUnlocked, ids.toList()..sort());
  }
}

final unlockedSkinsProvider = NotifierProvider<UnlockedSkinsNotifier, Set<String>>(UnlockedSkinsNotifier.new);
