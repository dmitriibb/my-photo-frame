import 'package:flutter/material.dart';

import '../data/card_repository.dart';
import '../data/models.dart';

class DeletedScreen extends StatefulWidget {
  const DeletedScreen({super.key, required this.repository});

  final CardRepository repository;

  @override
  State<DeletedScreen> createState() => _DeletedScreenState();
}

class _DeletedScreenState extends State<DeletedScreen> {
  late Future<(List<Collection>, List<MemoryCard>)> _deleted;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _deleted = _loadDeleted();
  }

  Future<(List<Collection>, List<MemoryCard>)> _loadDeleted() async => (
    await widget.repository.listDeletedCollections(),
    await widget.repository.listDeletedCards(),
  );

  Future<void> _restore(MemoryCard card) async {
    try {
      await widget.repository.restoreCard(card.id);
      if (mounted) {
        setState(() {
          _refresh();
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not restore card: $error')),
        );
      }
    }
  }

  Future<void> _restoreCollection(Collection collection) async {
    try {
      await widget.repository.restoreCollection(collection.id);
      if (mounted) setState(_refresh);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not restore collection: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Deleted')),
    body: SafeArea(
      top: false,
      child: FutureBuilder<(List<Collection>, List<MemoryCard>)>(
        future: _deleted,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load Deleted: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (collections, cards) = snapshot.data!;
          if (collections.isEmpty && cards.isEmpty) {
            return const Center(
              child: Text('No deleted cards or collections.'),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final collection in collections)
                Card(
                  color: Colors.white,
                  child: ListTile(
                    leading: const Icon(Icons.collections_outlined),
                    title: Text(collection.name),
                    subtitle: Text(
                      'Removed after ${_date(collection.purgeAt!)}',
                    ),
                    trailing: TextButton(
                      onPressed: () => _restoreCollection(collection),
                      child: const Text('Restore'),
                    ),
                  ),
                ),
              for (final card in cards)
                Builder(
                  builder: (context) {
                    final purgeDay = card.purgeAt!.toLocal();
                    return Card(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 88,
                              height: 88,
                              child: Image.file(
                                widget.repository.photoFile(card),
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(card.displayDate),
                                  Text(
                                    'Removed after ${_date(purgeDay)}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                  TextButton(
                                    onPressed: () => _restore(card),
                                    child: const Text('Restore'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    ),
  );

  String _date(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}
