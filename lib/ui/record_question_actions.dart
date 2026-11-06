import 'package:flutter/material.dart';

class RecordQuestionActions extends StatelessWidget {
  const RecordQuestionActions({
    super.key,
    required this.options,
    required this.selectedIds,
    required this.busy,
    required this.onSelect,
    required this.onCancel,
  });
  final List options, selectedIds;
  final bool busy;
  final ValueChanged<int> onSelect;
  final VoidCallback onCancel;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < options.length; i++)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              minimumSize: const Size(48, 48),
            ),
            onPressed: busy || selectedIds.contains(options[i]['id'])
                ? null
                : () => onSelect(options[i]['id'] as int),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(options[i]['label'] as String)),
                if (selectedIds.contains(options[i]['id']))
                  const Padding(
                    padding: EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle_outline, size: 18),
                  ),
              ],
            ),
          ),
        ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: busy ? null : onCancel,
            child: const Text('取消操作'),
          ),
        ],
      ),
    ],
  );
}
