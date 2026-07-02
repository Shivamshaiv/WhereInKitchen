import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A barcode lookup source we track usage for, with its human label and any
/// known free-tier daily cap (null = effectively unlimited / be-polite only).
class BarcodeSourceInfo {
  const BarcodeSourceInfo({
    required this.source,
    required this.label,
    required this.dailyLimit,
    this.note,
  });

  final String source;
  final String label;
  final int? dailyLimit;
  final String? note;
}

/// The barcode databases the app queries, in the order they're tried.
///
/// Open*Facts are free and unmetered (they only ask for a polite User-Agent);
/// UPCitemdb's trial endpoint is capped at 100 lookups/day per IP.
const List<BarcodeSourceInfo> kBarcodeSources = [
  BarcodeSourceInfo(
    source: 'open_food_facts',
    label: 'Open Food Facts',
    dailyLimit: null,
    note: 'Free · groceries & food',
  ),
  BarcodeSourceInfo(
    source: 'open_beauty_facts',
    label: 'Open Beauty Facts',
    dailyLimit: null,
    note: 'Free · cosmetics & care',
  ),
  BarcodeSourceInfo(
    source: 'open_products_facts',
    label: 'Open Products Facts',
    dailyLimit: null,
    note: 'Free · general products',
  ),
  BarcodeSourceInfo(
    source: 'open_pet_food_facts',
    label: 'Open Pet Food Facts',
    dailyLimit: null,
    note: 'Free · pet food',
  ),
  BarcodeSourceInfo(
    source: 'upcitemdb',
    label: 'UPCitemdb (trial)',
    dailyLimit: 100,
    note: 'Trial · 100 lookups/day',
  ),
];

/// Immutable snapshot of tracked barcode API usage.
class ApiUsageSnapshot {
  const ApiUsageSnapshot({
    required this.date,
    required this.today,
    required this.total,
  });

  /// The day (yyyy-mm-dd) the [today] counts belong to.
  final String date;

  /// Calls made today, keyed by source.
  final Map<String, int> today;

  /// All-time calls, keyed by source.
  final Map<String, int> total;

  int todayFor(String source) => today[source] ?? 0;
  int totalFor(String source) => total[source] ?? 0;

  int get todayAll => today.values.fold(0, (a, b) => a + b);
  int get totalAll => total.values.fold(0, (a, b) => a + b);

  static const empty = ApiUsageSnapshot(date: '', today: {}, total: {});
}

/// Tracks how many calls we make to each barcode lookup API, so users can see
/// their usage against free-tier daily limits. Counts are stored locally on
/// the device (limits like UPCitemdb's are enforced per IP/device anyway).
class ApiUsageService {
  static const _key = 'barcode_api_usage_v1';

  SharedPreferences? _prefs;

  Future<SharedPreferences> get _sp async =>
      _prefs ??= await SharedPreferences.getInstance();

  static String _todayKey([DateTime? now]) {
    final d = now ?? DateTime.now();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  Map<String, dynamic> _read(SharedPreferences prefs) {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) {
      return {'date': _todayKey(), 'today': {}, 'total': {}};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded['today'] ??= <String, dynamic>{};
      decoded['total'] ??= <String, dynamic>{};
      decoded['date'] ??= _todayKey();
      return decoded;
    } catch (_) {
      return {'date': _todayKey(), 'today': {}, 'total': {}};
    }
  }

  /// Records a single call to [source]. Rolls the daily bucket over at midnight.
  Future<void> recordCall(String source) async {
    final prefs = await _sp;
    final data = _read(prefs);
    final today = _todayKey();

    if (data['date'] != today) {
      data['date'] = today;
      data['today'] = <String, dynamic>{};
    }

    final todayMap = Map<String, dynamic>.from(data['today'] as Map);
    todayMap[source] = ((todayMap[source] as num?)?.toInt() ?? 0) + 1;
    data['today'] = todayMap;

    final totalMap = Map<String, dynamic>.from(data['total'] as Map);
    totalMap[source] = ((totalMap[source] as num?)?.toInt() ?? 0) + 1;
    data['total'] = totalMap;

    await prefs.setString(_key, jsonEncode(data));
  }

  Future<ApiUsageSnapshot> load() async {
    final prefs = await _sp;
    final data = _read(prefs);
    final today = _todayKey();

    // If the stored day is stale, present an empty "today".
    final storedDate = data['date'] as String? ?? today;
    final todayMap = storedDate == today
        ? _intMap(data['today'])
        : <String, int>{};

    return ApiUsageSnapshot(
      date: today,
      today: todayMap,
      total: _intMap(data['total']),
    );
  }

  Future<void> reset() async {
    final prefs = await _sp;
    await prefs.remove(_key);
  }

  Map<String, int> _intMap(dynamic raw) {
    if (raw is! Map) return {};
    return raw.map(
      (key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0),
    );
  }
}
