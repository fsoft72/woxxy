// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart';

import '../../funcs/utils.dart';
import '../../services/send_queue_controller.dart';

/// How many waiting files are listed before "...and N more".
const int QUEUE_PREVIEW_COUNT = 3;

/// How many finished files are listed (only shown while the list is short).
const int COMPLETED_PREVIEW_LIMIT = 5;

/// Summary of the send queue: completed counter, next files and recently finished ones.
class QueueSummary extends StatelessWidget {
  final List<QueuedFile> queue;
  final List<QueuedFile> completed;
  final int totalCompleted;
  final VoidCallback onCancelAll;

  const QueueSummary({
    super.key,
    required this.queue,
    required this.completed,
    required this.totalCompleted,
    required this.onCancelAll,
  });

  @override
  Widget build(BuildContext context) {
    final totalFiles = completed.length + queue.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'File Queue: $totalCompleted/$totalFiles completed',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (queue.isNotEmpty)
                TextButton(
                  onPressed: onCancelAll,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Cancel All'),
                ),
            ],
          ),
          if (queue.isNotEmpty) _buildNext(context),
          if (completed.isNotEmpty && completed.length <= COMPLETED_PREVIEW_LIMIT) _buildCompleted(),
        ],
      ),
    );
  }

  Widget _buildNext(BuildContext context) {
    final shown = queue.length < QUEUE_PREVIEW_COUNT ? queue.length : QUEUE_PREVIEW_COUNT;
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Next in queue:', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          for (int i = 0; i < shown; i++)
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 2.0),
              child: Text(
                '${i + 1}. ${queue[i].name} (${formatBytes(queue[i].size)})',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (queue.length > QUEUE_PREVIEW_COUNT)
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 2.0),
              child: Text(
                '...and ${queue.length - QUEUE_PREVIEW_COUNT} more',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.primary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompleted() {
    return Padding(
      padding: const EdgeInsets.only(top: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recently completed:', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          for (final file in completed.reversed)
            Padding(
              padding: const EdgeInsets.only(left: 8.0, top: 2.0),
              child: Row(
                children: [
                  Icon(
                    file.isCompleted ? Icons.check_circle : Icons.error,
                    size: 12,
                    color: file.isCompleted ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      file.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: file.isCompleted ? Colors.black87 : Colors.red,
                        decoration: file.isFailed ? TextDecoration.lineThrough : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
