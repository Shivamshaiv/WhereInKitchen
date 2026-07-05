import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wherein_kitchen/models/household.dart';
import 'package:wherein_kitchen/models/measure.dart';
import 'package:wherein_kitchen/providers/providers.dart';
import 'package:wherein_kitchen/services/api_usage_service.dart';

/// App settings, including barcode API usage stats so the user can keep an eye
/// on free-tier limits (e.g. UPCitemdb's 100 lookups/day).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usageAsync = ref.watch(apiUsageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(apiUsageProvider),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const _HomeSection(),
          Text(
            'Measurement units',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'How sizes are shown across the room designer and shelves.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          SegmentedButton<UnitSystem>(
            segments: const [
              ButtonSegment(
                value: UnitSystem.metric,
                label: Text('Centimetres'),
                icon: Icon(Icons.straighten),
              ),
              ButtonSegment(
                value: UnitSystem.imperial,
                label: Text('Feet & inches'),
              ),
            ],
            selected: {ref.watch(unitSystemProvider)},
            onSelectionChanged: (s) =>
                ref.read(unitSystemProvider.notifier).setSystem(s.first),
          ),
          const Divider(height: 32),
          Text(
            'Appearance',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
            ],
            selected: {ref.watch(themeModeProvider)},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).setMode(s.first),
          ),
          const Divider(height: 32),
          Text(
            'Kitchen guides',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Reference heights the wall designer shows and snaps to.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          _HeightSetting(
            title: 'Counter height',
            provider: counterHeightProvider,
            min: 60,
            max: 120,
          ),
          _HeightSetting(
            title: 'Wall-cabinet height',
            provider: wallCabinetHeightProvider,
            min: 120,
            max: 200,
          ),
          const Divider(height: 32),
          Text(
            'Barcode lookups',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'When you scan a product, these databases are queried in order and '
            'the app stops at the first match. Counts are for this device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          usageAsync.when(
            data: (snapshot) => _UsageCard(snapshot: snapshot),
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('Could not load usage: $e'),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await ref.read(apiUsageServiceProvider).reset();
              ref.invalidate(apiUsageProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    const SnackBar(content: Text('Usage stats reset')),
                  );
              }
            },
            icon: const Icon(Icons.restart_alt),
            label: const Text('Reset usage stats'),
          ),
        ],
      ),
    );
  }
}

/// "This home" section: who's in the home, leave, and (owner-only) remove.
class _HomeSection extends ConsumerWidget {
  const _HomeSection();

  String _shortUid(String uid) =>
      uid.length <= 6 ? uid : '${uid.substring(0, 6)}…';

  Future<void> _leave(
      BuildContext context, WidgetRef ref, Household home, String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave “${home.name}”?'),
        content: const Text(
            'You will lose access to this home\'s inventory. You can rejoin '
            'later with an invite code.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(householdRepositoryProvider).leaveHousehold(uid, home.id);
      // Re-point the active home to another of the user's homes (or none).
      final mine = ref.read(myHouseholdsProvider).valueOrNull ?? [];
      final next = mine.where((h) => h.id != home.id).firstOrNull;
      ref.read(householdIdProvider.notifier).state = next?.id;
      messenger.showSnackBar(SnackBar(content: Text('Left “${home.name}”')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Couldn’t leave — try again.')));
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref, Household home,
      String memberUid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text(
            'Remove member ${_shortUid(memberUid)} from “${home.name}”? They '
            'lose access immediately.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(householdRepositoryProvider).removeMember(home.id, memberUid);
      messenger.showSnackBar(const SnackBar(content: Text('Member removed')));
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Couldn’t remove — try again.')));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(householdProvider).valueOrNull;
    final uid = ref.watch(authStateProvider).valueOrNull?.uid;
    if (home == null || uid == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final isOwner = home.isOwner(uid);
    final others = home.members.where((m) => m != uid).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('This home', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(home.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          Text(
                            '${home.members.length} member${home.members.length == 1 ? '' : 's'}'
                            '${isOwner ? ' · you own this home' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _leave(context, ref, home, uid),
                      icon: Icon(Icons.logout, size: 18, color: scheme.error),
                      label: Text('Leave',
                          style: TextStyle(color: scheme.error)),
                    ),
                  ],
                ),
                if (isOwner && others.isNotEmpty) ...[
                  const Divider(height: 20),
                  for (final m in others)
                    Row(
                      children: [
                        const Icon(Icons.person_outline, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Member ${_shortUid(m)}')),
                        IconButton(
                          tooltip: 'Remove member',
                          icon: Icon(Icons.person_remove_outlined,
                              color: scheme.error),
                          onPressed: () => _remove(context, ref, home, m),
                        ),
                      ],
                    ),
                ],
              ],
            ),
          ),
        ),
        const Divider(height: 32),
      ],
    );
  }
}

/// A labelled slider for a persisted height preference (counter / wall units),
/// showing the value in the user's chosen units.
class _HeightSetting extends ConsumerStatefulWidget {
  const _HeightSetting({
    required this.title,
    required this.provider,
    required this.min,
    required this.max,
  });

  final String title;
  final StateNotifierProvider<DoublePrefNotifier, double> provider;
  final double min;
  final double max;

  @override
  ConsumerState<_HeightSetting> createState() => _HeightSettingState();
}

class _HeightSettingState extends ConsumerState<_HeightSetting> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final stored = ref.watch(widget.provider);
    final unitSystem = ref.watch(unitSystemProvider);
    final value =
        (_dragging ?? stored).clamp(widget.min, widget.max).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(widget.title,
                  style: Theme.of(context).textTheme.labelLarge),
            ),
            Text(
              formatLen(value, unitSystem),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max,
          divisions: (widget.max - widget.min).round(),
          onChanged: (v) => setState(() => _dragging = v),
          onChangeEnd: (v) {
            ref.read(widget.provider.notifier).set(v.roundToDouble());
            setState(() => _dragging = null);
          },
        ),
      ],
    );
  }
}

class _UsageCard extends StatelessWidget {
  const _UsageCard({required this.snapshot});

  final ApiUsageSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text('Today', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                Text(
                  '${snapshot.todayAll} call${snapshot.todayAll == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final src in kBarcodeSources) ...[
              const Divider(height: 18),
              _SourceRow(src: src, snapshot: snapshot),
            ],
            const Divider(height: 18),
            Row(
              children: [
                Text('All-time total',
                    style: Theme.of(context).textTheme.bodyMedium),
                const Spacer(),
                Text(
                  '${snapshot.totalAll}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.src, required this.snapshot});

  final BarcodeSourceInfo src;
  final ApiUsageSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = snapshot.todayFor(src.source);
    final total = snapshot.totalFor(src.source);
    final limit = src.dailyLimit;

    final bool nearLimit = limit != null && today >= limit * 0.8;
    final bool overLimit = limit != null && today >= limit;
    final barColor = overLimit
        ? scheme.error
        : nearLimit
            ? Colors.orange
            : scheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    src.label,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (src.note != null)
                    Text(
                      src.note!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              limit != null ? '$today / $limit' : '$today today',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: overLimit ? scheme.error : null,
                  ),
            ),
          ],
        ),
        if (limit != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (today / limit).clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: scheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
          if (overLimit)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Daily limit reached — lookups here may fail until tomorrow.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ),
        ],
        const SizedBox(height: 2),
        Text(
          'All-time: $total',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
