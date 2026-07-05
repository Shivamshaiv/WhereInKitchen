import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:wherein_kitchen/models/item.dart';

class ItemListTile extends StatelessWidget {
  const ItemListTile({
    super.key,
    required this.item,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  // Cache of decoded thumbnails keyed by their base64 string, so that
  // base64Decode does not run on every build()/scroll recycle.
  static final Map<String, Uint8List> _thumbCache = <String, Uint8List>{};

  final Item item;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    Widget? leading;
    if (item.thumbB64 != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.memory(
          _thumbCache[item.thumbB64!] ??=
              base64Decode(item.thumbB64!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
        ),
      );
    } else if (item.imageUrl != null) {
      leading = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          item.imageUrl!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
        ),
      );
    }

    return ListTile(
      leading: leading ?? const Icon(Icons.inventory_2_outlined),
      title: Text(item.name),
      subtitle: Text(
        [
          if (item.category.isNotEmpty) item.category,
          if (item.quantity.isNotEmpty) item.quantity,
        ].join(' · '),
      ),
      trailing: trailing,
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }
}
