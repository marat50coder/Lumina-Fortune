import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio.dart';
import '../models/models.dart';

class GameController extends ChangeNotifier {
  static const _key = 'lumina_fortune_save_v1';

  int coins = 80;
  int rTokens = 0;
  int chainLv = 0;
  int starLv = 0;
  int bellLv = 0;
  int rareLv = 0;
  int bestChain = 0;
  int bestScore = 0;
  int daysWon = 0;
  int dailyClaims = 0;
  int lastDailyEpoch = -1;
  bool music = true;
  bool sfx = true;
  bool vibrate = true;
  bool seenTip = false;

  final Set<String> unlockedZones = {'meadow'};
  final Set<String> fruits = {};
  final Set<String> rares = {};
  final Set<String> achievements = {};
  final Map<String, int> dayStars = {};

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        coins = m['coins'] as int? ?? coins;
        rTokens = m['r'] as int? ?? rTokens;
        chainLv = m['chainLv'] as int? ?? 0;
        starLv = m['starLv'] as int? ?? 0;
        bellLv = m['bellLv'] as int? ?? 0;
        rareLv = m['rareLv'] as int? ?? 0;
        bestChain = m['bestChain'] as int? ?? 0;
        bestScore = m['bestScore'] as int? ?? 0;
        daysWon = m['daysWon'] as int? ?? 0;
        dailyClaims = m['dailyClaims'] as int? ?? 0;
        lastDailyEpoch = m['lastDaily'] as int? ?? -1;
        music = m['music'] as bool? ?? true;
        sfx = m['sfx'] as bool? ?? true;
        vibrate = m['vibrate'] as bool? ?? true;
        seenTip = m['tip'] as bool? ?? false;
        unlockedZones
          ..clear()
          ..addAll(((m['zones'] as List?) ?? ['meadow']).cast<String>());
        fruits.addAll(((m['fruits'] as List?) ?? const []).cast<String>());
        rares.addAll(((m['rares'] as List?) ?? const []).cast<String>());
        achievements.addAll(((m['ach'] as List?) ?? const []).cast<String>());
        final ds = m['dayStars'] as Map<String, dynamic>? ?? {};
        dayStars
          ..clear()
          ..addAll(ds.map((k, v) => MapEntry(k, v as int)));
      } catch (_) {}
    }
    AudioHub.I.sfx = sfx;
    AudioHub.I.music = music;
    AudioHub.I.vibrate = vibrate;
    notifyListeners();
  }

  Future<void> persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
      _key,
      jsonEncode({
        'coins': coins,
        'r': rTokens,
        'chainLv': chainLv,
        'starLv': starLv,
        'bellLv': bellLv,
        'rareLv': rareLv,
        'bestChain': bestChain,
        'bestScore': bestScore,
        'daysWon': daysWon,
        'dailyClaims': dailyClaims,
        'lastDaily': lastDailyEpoch,
        'music': music,
        'sfx': sfx,
        'vibrate': vibrate,
        'tip': seenTip,
        'zones': unlockedZones.toList(),
        'fruits': fruits.toList(),
        'rares': rares.toList(),
        'ach': achievements.toList(),
        'dayStars': dayStars,
      }),
    );
  }

  int levelOf(UpgradeId id) => switch (id) {
        UpgradeId.chain => chainLv,
        UpgradeId.star => starLv,
        UpgradeId.bells => bellLv,
        UpgradeId.rare => rareLv,
      };

  void _setLevel(UpgradeId id, int v) {
    switch (id) {
      case UpgradeId.chain:
        chainLv = v;
      case UpgradeId.star:
        starLv = v;
      case UpgradeId.bells:
        bellLv = v;
      case UpgradeId.rare:
        rareLv = v;
    }
  }

  bool buyUpgrade(UpgradeId id) {
    final def = Catalog.upgrades.firstWhere((u) => u.id == id);
    final lv = levelOf(id);
    if (lv >= def.maxLevel) return false;
    final cost = Catalog.upgradeCost(def, lv);
    if (coins < cost || rTokens < def.rCost) return false;
    coins -= cost;
    rTokens -= def.rCost;
    _setLevel(id, lv + 1);
    if (lv + 1 >= 5) unlockAch('upgrade_5');
    persist();
    notifyListeners();
    return true;
  }

  bool zoneOpen(String id) => unlockedZones.contains(id);

  bool zoneCleared(ZoneDef z) {
    for (var d = 0; d < z.days; d++) {
      if ((dayStars['${z.id}_$d'] ?? 0) < 1) return false;
    }
    return true;
  }

  int nextPlayableDay(ZoneDef z) {
    for (var d = 0; d < z.days; d++) {
      if ((dayStars['${z.id}_$d'] ?? 0) < 1) return d;
    }
    return z.days - 1;
  }

  bool dayUnlocked(ZoneDef z, int day) {
    if (!zoneOpen(z.id)) return false;
    if (day <= 0) return true;
    return (dayStars['${z.id}_${day - 1}'] ?? 0) >= 1;
  }

  int starsOn(ZoneDef z, int day) => dayStars['${z.id}_$day'] ?? 0;

  bool canUnlock(ZoneDef z) {
    if (zoneOpen(z.id)) return true;
    if (z.unlockAfter != null && !zoneCleared(Catalog.zone(z.unlockAfter!))) {
      return false;
    }
    return coins >= z.coinUnlock && rTokens >= z.rUnlock;
  }

  bool unlockZone(ZoneDef z) {
    if (zoneOpen(z.id)) return true;
    if (!canUnlock(z)) return false;
    coins -= z.coinUnlock;
    rTokens -= z.rUnlock;
    unlockedZones.add(z.id);
    if (unlockedZones.length >= 5) unlockAch('all_zones');
    persist();
    notifyListeners();
    return true;
  }

  int todayEpoch() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).millisecondsSinceEpoch;
  }

  bool get dailyReady => lastDailyEpoch != todayEpoch();

  int get dailyIndex => dailyClaims % Catalog.dailyTable.length;

  bool claimDaily() {
    if (!dailyReady) return false;
    final gift = Catalog.dailyTable[dailyIndex];
    coins += gift.coins;
    rTokens += gift.r;
    dailyClaims += 1;
    lastDailyEpoch = todayEpoch();
    if (dailyClaims >= 7) unlockAch('daily_7');
    persist();
    notifyListeners();
    return true;
  }

  void markTip() {
    seenTip = true;
    persist();
  }

  void setFlag({bool? musicOn, bool? sfxOn, bool? vibeOn}) {
    if (musicOn != null) music = musicOn;
    if (sfxOn != null) {
      sfx = sfxOn;
      AudioHub.I.sfx = sfx;
    }
    if (vibeOn != null) {
      vibrate = vibeOn;
      AudioHub.I.vibrate = vibrate;
    }
    AudioHub.I.music = music;
    persist();
    notifyListeners();
  }

  void applyRun(DayResult r) {
    coins += r.coins;
    rTokens += r.rGained;
    if (r.success) daysWon += 1;
    if (r.chain > bestChain) bestChain = r.chain;
    if (r.score > bestScore) bestScore = r.score;
    final key = '${r.zoneId}_${r.day}';
    final prev = dayStars[key] ?? 0;
    if (r.stars > prev) dayStars[key] = r.stars;

    for (final id in r.collected) {
      final fruit = Catalog.fruits.where((f) => f.id == id);
      if (fruit.isNotEmpty) fruits.add(id);
      final rare = Catalog.rares.where((f) => f.id == id);
      if (rare.isNotEmpty) rares.add(id);
    }

    if (r.success) unlockAch('first_harvest');
    if (r.chain >= 10) unlockAch('chain_10');
    if (r.chain >= 20) unlockAch('chain_20');
    if (r.starHit) unlockAch('star_caller');
    if (r.bells >= 3) unlockAch('bell_trio');
    if (r.collected.contains('golden_fruit')) unlockAch('golden_finder');
    if (r.collected.contains('r_emblem')) unlockAch('r_finder');
    if (zoneCleared(Catalog.zone('meadow'))) unlockAch('meadow_clear');
    if (fruits.length >= 12) unlockAch('collector');

    final z = Catalog.zone(r.zoneId);
    if (zoneCleared(z)) {
      final i = Catalog.zones.indexWhere((e) => e.id == z.id);
      if (i >= 0 && i + 1 < Catalog.zones.length) {
        unlockedZones.add(Catalog.zones[i + 1].id);
        if (unlockedZones.length >= 5) unlockAch('all_zones');
      }
    }

    persist();
    notifyListeners();
  }

  void unlockAch(String id) {
    if (achievements.add(id)) {
      coins += 25;
    }
  }

  double get chainBonus => 1 + chainLv * 0.08;
  double get starMult => 1.6 + starLv * 0.15;
  double get bellRadius => 0.16 + bellLv * 0.018;
  double get rareChance => 0.06 + rareLv * 0.04;

  int extraObjects() => chainLv;
}

int starsFor({
  required int chain,
  required int caught,
  required int missed,
  required int goal,
  required int chainGoal,
  required bool success,
}) {
  if (!success) return 0;
  final extra = caught - goal;
  final niceChain = chain >= chainGoal;
  if (missed == 0 && (extra >= 1 || niceChain)) return 3;
  if (missed == 0) return 2;
  if (missed == 1 && (extra >= 2 || niceChain)) return 3;
  if (missed == 1) return 2;
  if (missed == 2 && extra >= 1) return 2;
  return 1;
}
