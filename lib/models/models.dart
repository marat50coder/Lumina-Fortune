import '../core/assets.dart';

enum UpgradeId { chain, star, bells, rare }

class ZoneDef {
  const ZoneDef({
    required this.id,
    required this.name,
    required this.blurb,
    required this.background,
    required this.days,
    required this.minCollect,
    required this.minChain,
    required this.unlockAfter,
    required this.coinUnlock,
    required this.rUnlock,
  });

  final String id;
  final String name;
  final String blurb;
  final String background;
  final int days;
  final int minCollect;
  final int minChain;
  final String? unlockAfter;
  final int coinUnlock;
  final int rUnlock;
}

class Collectible {
  const Collectible({
    required this.id,
    required this.name,
    required this.sprite,
    required this.rare,
  });

  final String id;
  final String name;
  final String sprite;
  final bool rare;
}

class AchievementDef {
  const AchievementDef({
    required this.id,
    required this.title,
    required this.detail,
    required this.goal,
  });

  final String id;
  final String title;
  final String detail;
  final int goal;
}

class UpgradeDef {
  const UpgradeDef({
    required this.id,
    required this.title,
    required this.detail,
    required this.baseCost,
    required this.rCost,
    required this.maxLevel,
  });

  final UpgradeId id;
  final String title;
  final String detail;
  final int baseCost;
  final int rCost;
  final int maxLevel;
}

class DayResult {
  const DayResult({
    required this.zoneId,
    required this.day,
    required this.score,
    required this.chain,
    required this.caught,
    required this.missed,
    required this.coins,
    required this.rGained,
    required this.starHit,
    required this.burst,
    required this.collected,
    required this.bells,
    required this.stars,
    required this.success,
  });

  final String zoneId;
  final int day;
  final int score;
  final int chain;
  final int caught;
  final int missed;
  final int coins;
  final int rGained;
  final bool starHit;
  final bool burst;
  final List<String> collected;
  final int bells;
  final int stars;
  final bool success;
}

class Catalog {
  static const zones = [
    ZoneDef(
      id: 'meadow',
      name: 'Sunny Meadow',
      blurb: 'A bright clearing where the first fruits ripen.',
      background: A.bgMeadow,
      days: 4,
      minCollect: 6,
      minChain: 6,
      unlockAfter: null,
      coinUnlock: 0,
      rUnlock: 0,
    ),
    ZoneDef(
      id: 'grove',
      name: 'Berry Grove',
      blurb: 'Dense berry bushes and sweeter clusters.',
      background: A.bgGrove,
      days: 4,
      minCollect: 8,
      minChain: 8,
      unlockAfter: 'meadow',
      coinUnlock: 120,
      rUnlock: 0,
    ),
    ZoneDef(
      id: 'bellwood',
      name: 'Bellwood',
      blurb: 'Old forest bells wait to wake the chain.',
      background: A.bgBellwood,
      days: 5,
      minCollect: 10,
      minChain: 10,
      unlockAfter: 'grove',
      coinUnlock: 220,
      rUnlock: 1,
    ),
    ZoneDef(
      id: 'glade',
      name: 'Golden Glade',
      blurb: 'Sun-gold objects shine between the pines.',
      background: A.bgGlade,
      days: 5,
      minCollect: 12,
      minChain: 12,
      unlockAfter: 'bellwood',
      coinUnlock: 360,
      rUnlock: 2,
    ),
    ZoneDef(
      id: 'ancient',
      name: 'Ancient Sun Forest',
      blurb: 'The oldest grove. Long chains. Rare light.',
      background: A.bgAncient,
      days: 6,
      minCollect: 14,
      minChain: 14,
      unlockAfter: 'glade',
      coinUnlock: 520,
      rUnlock: 3,
    ),
  ];

  static ZoneDef zone(String id) => zones.firstWhere((z) => z.id == id);

  static const dayTitles = {
    'meadow': ['First Drop', 'Crosswind', 'The Warden', 'Harvest Trial'],
    'grove': ['Berry Rush', 'Tangled Lane', 'Twin Clappers', 'Night Cluster'],
    'bellwood': ['Echo Path', 'Three Tolls', 'Narrow Gate', 'Bell Storm', 'Last Chorus'],
    'glade': ['Gold Drift', 'Sun Trap', 'Split Catch', 'Gilded Wind', 'Vault Day'],
    'ancient': ['Old Light', 'Root Maze', 'Seed Fall', 'Relic Wind', 'Sun Keep', 'Final Grove'],
  };

  static String dayTitle(String zoneId, int day) {
    final list = dayTitles[zoneId];
    if (list != null && day >= 0 && day < list.length) return list[day];
    return 'Day ${day + 1}';
  }

  static const fruits = [
    Collectible(id: 'apple', name: 'Sun Apple', sprite: A.fruitApple, rare: false),
    Collectible(id: 'orange', name: 'Grove Orange', sprite: A.fruitOrange, rare: false),
    Collectible(id: 'lemon', name: 'Bright Lemon', sprite: A.fruitLemon, rare: false),
    Collectible(id: 'pear', name: 'Meadow Pear', sprite: A.fruitPear, rare: false),
    Collectible(id: 'peach', name: 'Dusk Peach', sprite: A.fruitPeach, rare: false),
    Collectible(id: 'plum', name: 'Violet Plum', sprite: A.fruitPlum, rare: false),
    Collectible(id: 'cherry', name: 'Twin Cherries', sprite: A.fruitCherry, rare: false),
    Collectible(id: 'pomegranate', name: 'Crown Fruit', sprite: A.fruitPomegranate, rare: false),
    Collectible(id: 'strawberry', name: 'Wild Strawberry', sprite: A.berryStrawberry, rare: false),
    Collectible(id: 'raspberry', name: 'Ruby Raspberry', sprite: A.berryRaspberry, rare: false),
    Collectible(id: 'blueberry', name: 'Sky Blueberry', sprite: A.berryBlueberry, rare: false),
    Collectible(id: 'blackberry', name: 'Night Blackberry', sprite: A.berryBlackberry, rare: false),
    Collectible(id: 'blackcurrant', name: 'Blackcurrant', sprite: A.berryBlackcurrant, rare: false),
    Collectible(id: 'gooseberry', name: 'Gooseberry', sprite: A.berryGooseberry, rare: false),
    Collectible(id: 'straw_pair', name: 'Berry Pair', sprite: A.berryStrawPair, rare: false),
    Collectible(id: 'blue_cluster', name: 'Blue Cluster', sprite: A.berryBlueCluster, rare: false),
  ];

  static const rares = [
    Collectible(id: 'sun_star', name: 'Lumina Sun Star', sprite: A.sunStar, rare: true),
    Collectible(id: 'r_emblem', name: 'Golden R', sprite: A.rEmblem, rare: true),
    Collectible(id: 'golden_fruit', name: 'Rare Golden Fruit', sprite: A.goldenFruit, rare: true),
    Collectible(id: 'seed', name: 'Lumina Seed', sprite: A.seed, rare: true),
    Collectible(id: 'bell_gold', name: 'Gold Forest Bell', sprite: A.bellGold, rare: true),
    Collectible(id: 'bell_sun', name: 'Sun Bell', sprite: A.bellSun, rare: true),
    Collectible(id: 'coin_sun', name: 'Sun Coin', sprite: A.coinSun, rare: true),
    Collectible(id: 'coin_r', name: 'R Coin', sprite: A.coinR, rare: true),
  ];

  static const upgrades = [
    UpgradeDef(
      id: UpgradeId.chain,
      title: 'Chain Harvest',
      detail: 'Longer chains and fuller groves.',
      baseCost: 50,
      rCost: 0,
      maxLevel: 8,
    ),
    UpgradeDef(
      id: UpgradeId.star,
      title: 'Star Power',
      detail: 'Stronger Lumina Burst and extra coins.',
      baseCost: 60,
      rCost: 0,
      maxLevel: 8,
    ),
    UpgradeDef(
      id: UpgradeId.bells,
      title: 'Bell Chorus',
      detail: 'Richer bells and a wider wake pulse.',
      baseCost: 55,
      rCost: 0,
      maxLevel: 8,
    ),
    UpgradeDef(
      id: UpgradeId.rare,
      title: 'Rare Light',
      detail: 'More golden fruit, seeds, and R emblems.',
      baseCost: 70,
      rCost: 1,
      maxLevel: 6,
    ),
  ];

  static const achievements = [
    AchievementDef(id: 'first_harvest', title: 'First Harvest', detail: 'Finish any grove day.', goal: 1),
    AchievementDef(id: 'chain_10', title: 'Chain Keeper', detail: 'Create a chain of 10.', goal: 10),
    AchievementDef(id: 'chain_20', title: 'Chain Master', detail: 'Create a chain of 20.', goal: 20),
    AchievementDef(id: 'star_caller', title: 'Star Caller', detail: 'Wake the Lumina Sun Star.', goal: 1),
    AchievementDef(id: 'bell_trio', title: 'Bell Trio', detail: 'Ring three bells in one day.', goal: 3),
    AchievementDef(id: 'golden_finder', title: 'Golden Finder', detail: 'Collect a rare golden fruit.', goal: 1),
    AchievementDef(id: 'r_finder', title: 'R Keeper', detail: 'Collect a golden R emblem.', goal: 1),
    AchievementDef(id: 'meadow_clear', title: 'Meadow Cleared', detail: 'Complete every Sunny Meadow day.', goal: 4),
    AchievementDef(id: 'all_zones', title: 'Grove Walker', detail: 'Unlock every forest zone.', goal: 5),
    AchievementDef(id: 'collector', title: 'Fruit Album', detail: 'Collect 12 different fruits.', goal: 12),
    AchievementDef(id: 'daily_7', title: 'Week of Light', detail: 'Claim 7 daily rewards.', goal: 7),
    AchievementDef(id: 'upgrade_5', title: 'Grove Crafter', detail: 'Raise any upgrade to level 5.', goal: 5),
  ];

  static const dailyTable = [
    (coins: 40, r: 0, label: 'Coin Purse'),
    (coins: 55, r: 0, label: 'Berry Gift'),
    (coins: 70, r: 0, label: 'Sunny Bundle'),
    (coins: 40, r: 1, label: 'R Spark'),
    (coins: 90, r: 0, label: 'Gold Basket'),
    (coins: 110, r: 0, label: 'Grove Cache'),
    (coins: 80, r: 2, label: 'Lumina Feast'),
  ];

  static int upgradeCost(UpgradeDef def, int level) {
    return def.baseCost + level * (def.baseCost * 0.7).round();
  }
}
