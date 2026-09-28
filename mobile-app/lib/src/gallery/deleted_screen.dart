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
  late Future<List<MemoryCard>> _cards;

  @override
  void initState() {
    super.initState();
    _cards = widget.repository.listDeletedCards();
  }

  Future<void> _restore(MemoryCard card) async {
    try {
      await widget.repository.restoreCard(card.id);
      if (mounted) {
        setState(() {
          _cards = widget.repository.listDeletedCards();
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

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Deleted')),
    body: SafeArea(
      top: false,
      child: FutureBuilder<List<MemoryCard>>(
        future: _cards,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Could not load Deleted: ${snapshot.error}'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.data!.isEmpty) {
            return const Center(child: Text('No deleted cards.'));
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              final card = snapshot.data![index];
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
                              'Removed after ${purgeDay.year}-${purgeDay.month.toString().padLeft(2, '0')}-${purgeDay.day.toString().padLeft(2, '0')}',
                              style: Theme.of(context).textTheme.bodySmall,
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
          );
        },
      ),
    ),
  );
}
