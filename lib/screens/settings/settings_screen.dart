import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
