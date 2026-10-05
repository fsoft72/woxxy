import 'package:flutter/material.dart';

/// Card with the file currently being sent: name, position in the queue, progress bar and speed.
class TransferProgressCard extends StatelessWidget {
  final String fileName;

  /// Position text such as "File 2 of 5"; null hides it
  final String? queueLabel;

  /// 0 to 100
  final double progress;
  final double speedMBps;
  final bool complete;
  final VoidCallback onCancel;

  const TransferProgressCard({
    super.key,
    required this.fileName,
    required this.queueLabel,
    required this.progress,
    required this.speedMBps,
    required this.complete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.upload_file, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, overflow: TextOverflow.ellipsis),
                    ),
                    if (queueLabel != null)
                      Text(queueLabel!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              if (!complete)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: onCancel,
                  tooltip: 'Cancel all transfers',
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: const EdgeInsets.all(0),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress / 100,
            backgroundColor: Colors.grey.shade300,
            color: complete ? Colors.green : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                complete ? 'Completed' : '${progress.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: complete ? Colors.green : null,
                  fontWeight: complete ? FontWeight.bold : null,
                ),
              ),
              Text('${speedMBps.toStringAsFixed(2)} MB/s'),
            ],
          ),
        ],
      ),
    );
  }
}
